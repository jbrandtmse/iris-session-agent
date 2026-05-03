/// <p>Per-turn orchestrator — the capstone of Epic 2. Wires together
/// every Story 2.1–2.11 deliverable into a single 10-step state machine
/// invoked once per portal-tab user turn. The hyperevent dispatch in
/// Epic 3 (chat-panel ZenMethod) and the Inspection-portal dispatch in
/// Epic 7 both call <method>RunTurn</method> as their only entry point.</p>
///
/// <p><b>Concurrency contract.</b> Each turn calls
/// <method>SessionAgent.Chat.History.LoadOrCreate</method> which acquires
/// the per-row exclusive lock via <code>%OpenId(id, 4)</code>. Every code
/// path through <method>RunTurn</method> MUST <method>%Save</method> (or
/// <method>%Close</method>) the chat-history OREF so the lock is released
/// before <method>RunTurn</method> returns — there are NO early returns
/// that hold the lock. Two browser tabs hitting the same conversation
/// tuple thus serialize naturally at the IRIS lock queue (FR46, NFR-P4,
/// architecture line 611).</p>
///
/// <p><b>Never-throw contract (FR37).</b> All errors — concurrent-tab
/// lock conflict, agent-not-configured, agent-disabled, unsupported
/// provider, provider error envelope, max-iteration cap — surface to the
/// browser as a structured <CLASS>SessionAgent.Agent.TurnResult</CLASS>
/// with the operator-readable message in
/// <property>AssistantMarkdown</property>. The method NEVER throws.</p>
///
/// <p><b>Mock-provider injection for tests (Story 2.12 dev choice — option
/// B).</b> Provider instantiation is extracted into the
/// <method>InstantiateProvider</method> ClassMethod so test subclasses
/// can intercept and return a
/// <CLASS>SessionAgent.Test.MockOpenAIProvider</CLASS> subclass instead
/// of the production <CLASS>SessionAgent.LLM.OpenAIProvider</CLASS>. This
/// keeps the orchestration entry point identical between production and
/// tests; only the provider-construction call is overridable.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 2.12</a> (lines 1064–1096) — AC source.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md</a>
/// line 116 (concurrency lock); line 272 (MaxIterationsPerTurn);
/// line 340 (calibration constants); line 331 (class location); line 611
/// (lock-release pattern).</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/prd.md">prd.md</a>
/// FR29, FR37, FR46, FR55–FR58, NFR-O2, NFR-P4, NFR-S4.</li>
/// <li><a href="../../../.claude/rules/iris-objectscript-basics.md">.claude/rules/iris-objectscript-basics.md</a>
/// §"Naming Conventions", §"QUIT Statement Restrictions in Try/Catch
/// Blocks", §"Timestamp and Encoding Standards".</li>
/// </ul>
Class SessionAgent.Agent.AgentLoop Extends %RegisteredObject
{

/// <p>Maximum number of provider round-trips per turn before the loop
/// emits the synthetic "Max iterations reached" assistant turn. Per
/// architecture line 340 calibration — bounds runaway tool-call loops
/// (e.g., a model that keeps re-issuing the same tool_use block) so
/// the operator sees a bounded chat panel rather than an indefinite
/// hang.</p>
Parameter MaxIterationsPerTurn As INTEGER = 10;

/// <p>Per-call provider HTTP timeout, in seconds. Mirrors FR29 +
/// architecture line 340; the concrete provider sets this on
/// <code>%Net.HttpRequest.Timeout</code>. Locked here so a regression
/// flips a static-time assertion at the orchestration layer.</p>
Parameter PerCallProviderTimeoutSec As INTEGER = 90;

/// <p>Run one user turn through the full state machine. Returns a
/// <CLASS>SessionAgent.Agent.TurnResult</CLASS> on every code path —
/// success, validation error, lock conflict, provider error, max
/// iterations. NEVER throws (FR37).</p>
///
/// <p>10-step orchestration:</p>
/// <ol>
/// <li>Build <CLASS>SessionAgent.Agent.CallerContext</CLASS> at the
/// trust boundary (NFR-S6 — tools NEVER read <code>$NAMESPACE</code>).</li>
/// <li>Acquire chat-history exclusive lock via
/// <method>SessionAgent.Chat.History.LoadOrCreate</method>.</li>
/// <li>Read live <CLASS>SessionAgent.Config.Agent</CLASS> row
/// (NFR-O2 hot config — re-read every turn).</li>
/// <li>Append the user message to <property>TurnsJson</property>.</li>
/// <li>Enumerate registered tools via
/// <method>SessionAgent.Tool.Registry.ListTools</method>.</li>
/// <li>Resolve the system prompt (per-row override or per-agent default).</li>
/// <li>Drive the iteration loop bounded by
/// <parameter>MaxIterationsPerTurn</parameter>; on
/// <code>tool_use</code>, dispatch each tool via
/// <method>SessionAgent.Tool.Registry.Dispatch</method> and append the
/// <code>tool_result</code> turn; on terminal stop reason, break.</li>
/// <li>Persist the chat-history row via <method>%Save</method> — releases
/// the per-row lock unconditionally.</li>
/// <li>Build the <CLASS>SessionAgent.Agent.TurnResult</CLASS>: final
/// assistant text, usage rollup, duration, tool-call card payloads.</li>
/// <li>Return.</li>
/// </ol>
ClassMethod RunTurn(pAgentName As %String, pSessionKey As %String, pPortalUser As %String, pUserText As %String, pContextHints As %DynamicObject = "") As SessionAgent.Agent.TurnResult
{
    ; Initialize the return value before any try/catch so every code
    ; path can populate it without violating the "argumentless quit
    ; inside Try/Catch" rule (project rule §"QUIT Statement Restrictions").
    Set tResult = ##class(SessionAgent.Agent.TurnResult).%New()
    Set tResult.AssistantMarkdown = ""
    Set tResult.UsageRollup = ##class(%DynamicObject).%New()
    Do tResult.UsageRollup.%Set("input_tokens", 0)
    Do tResult.UsageRollup.%Set("output_tokens", 0)
    Do tResult.UsageRollup.%Set("cache_creation_input_tokens", 0)
    Do tResult.UsageRollup.%Set("cache_read_input_tokens", 0)
    Set tResult.DurationMs = 0
    Set tResult.ToolCallsRendered = ##class(%DynamicArray).%New()

    Set tStartHorolog = $ZHorolog
    Set tHist = $$$NULLOREF

    Try {
        ; ─────────────────────────────────────────────────────────────
        ; Step 1 — Build CallerContext at the trust boundary.
        ; ─────────────────────────────────────────────────────────────
        Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
        Set tCtx.AgentName = pAgentName
        Set tCtx.PortalUser = pPortalUser
        Set tCtx.Namespace = $NAMESPACE
        If pAgentName = "session-inspection" {
            Set tCtx.IrisSessionId = pSessionKey
            Set tCtx.SearchSessionKey = ""
        } Else {
            Set tCtx.IrisSessionId = ""
            Set tCtx.SearchSessionKey = pSessionKey
        }

        ; ─────────────────────────────────────────────────────────────
        ; Step 2 — Load chat history with exclusive lock.
        ; ─────────────────────────────────────────────────────────────
        Set tLoadStatus = $$$OK
        Set tHist = ##class(SessionAgent.Chat.History).LoadOrCreate(pAgentName, pSessionKey, pPortalUser, "", .tLoadStatus)
        If '$IsObject(tHist) {
            ; Lock conflict / persistence error — never-throw envelope.
            Set tResult.AssistantMarkdown = "Concurrent turn in progress; please wait."
            ; tHist is NULLOREF — no lock to release, no Save needed.
            Quit
        }
        Set tCtx.ChatHistoryId = tHist.%Id()

        ; ─────────────────────────────────────────────────────────────
        ; Step 3 — Read live Config.Agent (NFR-O2 hot config).
        ; ─────────────────────────────────────────────────────────────
        Set tConfig = ##class(SessionAgent.Config.Agent).AgentNameIdxOpen(pAgentName)
        If '$IsObject(tConfig) {
            Set tResult.AssistantMarkdown = "Agent not configured: " _ pAgentName
            ; Save+release the lock before returning (no actual mutation
            ; was made, but we own the lock — release it).
            Do ..ReleaseChatHistory(tHist)
            Set tHist = $$$NULLOREF
            Quit
        }
        If tConfig.Enabled = 0 {
            Set tResult.AssistantMarkdown = "Agent " _ pAgentName _ " is disabled"
            Do ..ReleaseChatHistory(tHist)
            Set tHist = $$$NULLOREF
            Quit
        }

        ; ─────────────────────────────────────────────────────────────
        ; Step 4 — Append user message to TurnsJson.
        ; ─────────────────────────────────────────────────────────────
        Set tTurns = ..LoadTurns(tHist)
        Set tUserTurn = ##class(%DynamicObject).%New()
        Do tUserTurn.%Set("role", "user")
        Set tUserContent = ##class(%DynamicArray).%New()
        Set tUserBlock = ##class(%DynamicObject).%New()
        Do tUserBlock.%Set("type", "text")
        Do tUserBlock.%Set("text", pUserText)
        Do tUserContent.%Push(tUserBlock)
        Do tUserTurn.%Set("content", tUserContent)
        Do tTurns.%Push(tUserTurn)

        ; ─────────────────────────────────────────────────────────────
        ; Step 5 — Tool definitions for the loop.
        ; ─────────────────────────────────────────────────────────────
        Set tToolDefs = ##class(SessionAgent.Tool.Registry).ListTools()

        ; ─────────────────────────────────────────────────────────────
        ; Step 6 — System prompt (per-row override or per-agent default).
        ; ─────────────────────────────────────────────────────────────
        Set tSysPrompt = ""
        If tConfig.SystemPromptOverride '= "" {
            Set tSysPrompt = tConfig.SystemPromptOverride
        } Else {
            Set tSysPrompt = ##class(SessionAgent.Config.AgentDefaults).GetSystemPrompt(pAgentName)
        }

        ; ─────────────────────────────────────────────────────────────
        ; Step 7 — Iteration loop. Bounded by MaxIterationsPerTurn.
        ; ─────────────────────────────────────────────────────────────
        Set tIter = 0
        Set tStop = 0
        Set tHitMaxIter = 0
        Set tFinalAssistantText = ""

        While (tIter < ..#MaxIterationsPerTurn) && (tStop = 0) {
            Set tIter = tIter + 1

            ; Step 7a — instantiate provider (mockable hook, option B).
            Set tProvider = ..InstantiateProvider(tConfig)
            If '$IsObject(tProvider) {
                Set tFinalAssistantText = "Unsupported provider: " _ tConfig.Provider
                ; Append a synthetic assistant turn so the persisted history
                ; mirrors what the user saw in the chat panel.
                Do ..AppendAssistantText(tTurns, tFinalAssistantText)
                Set tStop = 1
                Quit ; argumentless — exits the While
            }

            ; Provider concretes read model/temp/max_tokens from
            ; ConfigAgent and resolve credentials from EnvVarName +
            ; CredentialName via the back-channel property.
            Set tProvider.ConfigAgent = tConfig

            ; Step 7b — invoke the provider via the abstract template.
            Set tProvResp = ##class(SessionAgent.Agent.ProviderResponse).%New()
            Set tCacheCfg = ##class(%DynamicObject).%New()
            Set tInvokeSC = tProvider.Invoke(tTurns, tToolDefs, tSysPrompt, tCacheCfg, tConfig, tCtx, .tProvResp)
            If $$$ISERR(tInvokeSC) {
                ; Provider abstract returned hard %Status error (rare —
                ; the template is supposed to populate the error envelope).
                Set tFinalAssistantText = "Provider error: " _ $System.Status.GetErrorText(tInvokeSC)
                Do ..AppendAssistantText(tTurns, tFinalAssistantText)
                Set tStop = 1
                Quit
            }

            ; Roll up token usage for this round-trip.
            Do ..RollupUsage(tResult.UsageRollup, tProvResp.Usage)

            ; Step 7c — append the assistant turn (with the canonical
            ; Content array verbatim) to the in-memory history.
            Set tAssistantTurn = ##class(%DynamicObject).%New()
            Do tAssistantTurn.%Set("role", "assistant")
            Do tAssistantTurn.%Set("content", tProvResp.Content)
            Do tTurns.%Push(tAssistantTurn)

            ; Step 7d — branch on stop reason.
            If tProvResp.StopReason = "tool_use" {
                ; Iterate over content blocks; for each tool_use block,
                ; dispatch via the registry, then append a single
                ; tool_result turn whose content array carries one
                ; tool_result block per dispatched tool (Anthropic-shape).
                Set tToolResultBlocks = ##class(%DynamicArray).%New()
                If $IsObject(tProvResp.Content) {
                    Set tBlockIter = tProvResp.Content.%GetIterator()
                    While tBlockIter.%GetNext(.tBidx, .tBlock) {
                        If '$IsObject(tBlock) Continue
                        If tBlock.%Get("type") '= "tool_use" Continue

                        Set tBlockToolName = tBlock.%Get("name")
                        Set tBlockToolUseId = ""
                        If tBlock.%IsDefined("id") {
                            Set tBlockToolUseId = tBlock.%Get("id")
                        }
                        Set tBlockInput = ##class(%DynamicObject).%New()
                        If tBlock.%IsDefined("input") {
                            Set tBlockInput = tBlock.%Get("input")
                        }

                        ; Dispatch via the trust-boundary registry.
                        Set tToolResult = ##class(%DynamicObject).%New()
                        Do ##class(SessionAgent.Tool.Registry).Dispatch(tBlockToolName, tCtx, tBlockInput, .tToolResult)

                        ; Build the canonical tool_result block.
                        Set tResultBlock = ##class(%DynamicObject).%New()
                        Do tResultBlock.%Set("type", "tool_result")
                        Do tResultBlock.%Set("tool_use_id", tBlockToolUseId)
                        Do tResultBlock.%Set("content", tToolResult.%ToJSON())
                        If $IsObject(tToolResult), tToolResult.%IsDefined("isError"), tToolResult.%Get("isError") = 1 {
                            Do tResultBlock.%Set("is_error", 1, "boolean")
                        }
                        Do tToolResultBlocks.%Push(tResultBlock)

                        ; Build the per-card UI payload for ToolCallsRendered.
                        Set tCard = ##class(%DynamicObject).%New()
                        Do tCard.%Set("name", tBlockToolName)
                        If $IsObject(tBlockInput) {
                            Do tCard.%Set("args", tBlockInput)
                        } Else {
                            Do tCard.%Set("args", ##class(%DynamicObject).%New())
                        }
                        Do tCard.%Set("result", tToolResult)
                        Set tCardStatus = "ok"
                        If $IsObject(tToolResult), tToolResult.%IsDefined("isError"), tToolResult.%Get("isError") = 1 {
                            Set tCardStatus = "error"
                        }
                        Do tCard.%Set("status", tCardStatus)
                        Do tResult.ToolCallsRendered.%Push(tCard)
                    }
                }

                ; Append the tool_result turn to the canonical history.
                Set tToolResultTurn = ##class(%DynamicObject).%New()
                Do tToolResultTurn.%Set("role", "user")
                Do tToolResultTurn.%Set("content", tToolResultBlocks)
                Do tTurns.%Push(tToolResultTurn)

                ; Continue the loop — provider gets another round-trip
                ; with the tool_result included in history.
            } Else {
                ; Terminal stop reason (end_turn, max_tokens,
                ; stop_sequence, error, or any unrecognized value) —
                ; harvest the final assistant text and break.
                Set tFinalAssistantText = ..ExtractAssistantText(tProvResp.Content)
                Set tStop = 1
            }

            ; Loop guard — if we hit max iterations after this round-trip
            ; and the model has not stopped, append the synthetic turn.
            If (tStop = 0) && (tIter >= ..#MaxIterationsPerTurn) {
                Set tHitMaxIter = 1
            }
        }

        If tHitMaxIter {
            Set tFinalAssistantText = "Max iterations reached. Please summarize."
            Do ..AppendAssistantText(tTurns, tFinalAssistantText)
        }

        ; ─────────────────────────────────────────────────────────────
        ; Step 8 — Save chat history (releases the lock).
        ; ─────────────────────────────────────────────────────────────
        Set tHist.UpdatedAt = $Translate($ZDateTime($ZTimeStamp, 3, 1), " ", "T") _ "Z"
        Do ..StoreTurns(tHist, tTurns)
        Do ..ReleaseChatHistory(tHist)
        Set tHist = $$$NULLOREF

        ; ─────────────────────────────────────────────────────────────
        ; Step 9 — Build TurnResult.
        ; ─────────────────────────────────────────────────────────────
        Set tResult.AssistantMarkdown = tFinalAssistantText
    }
    Catch ex {
        ; Defense in depth — never throw out of RunTurn (FR37). On any
        ; uncaught exception, build a structured envelope and best-effort
        ; release the chat-history lock.
        Set tResult.AssistantMarkdown = "AgentLoop exception: " _ ex.DisplayString()
        Try {
            If $IsObject(tHist) {
                Do ..ReleaseChatHistory(tHist)
            }
        }
        Catch releaseEx {
            ; Swallow — best-effort release; the OREF goes out of scope
            ; at the next argumentless quit so the lock will be released
            ; eventually anyway.
        }
        Set tHist = $$$NULLOREF
    }

    ; Step 10 — duration + return.
    Set tResult.DurationMs = $Normalize(($ZHorolog - tStartHorolog) * 1000, 0)
    Quit tResult
}

/// <p>Provider instantiation hook — option B from the Story 2.12 Dev
/// Notes. Production path returns the appropriate concrete LLM provider
/// for <property>pConfig.Provider</property>; tests inject a mock by
/// calling <method>SessionAgent.Agent.ProviderOverride.SetOverride</method>
/// before invoking <method>RunTurn</method> and clearing it after.
/// The singleton holder preserves OREF identity in-process — process-
/// private globals (<code>^||...</code>) cannot, because OREFs
/// stringify on assignment to a global node (they round-trip as the
/// literal string <code>"oref@class"</code> with <code>$IsObject</code>
/// returning 0).</p>
///
/// <p>Returns <code>$$$NULLOREF</code> for an unrecognized
/// <property>pConfig.Provider</property>; the caller surfaces this as
/// the structured envelope <code>"Unsupported provider: &lt;name&gt;"</code>.</p>
ClassMethod InstantiateProvider(pConfig As SessionAgent.Config.Agent) As SessionAgent.LLM.Provider
{
    ; Test override fast path — if the singleton holder has an OREF
    ; stashed, return it verbatim. Tests set the OREF in
    ; OnBeforeOneTest and clear it in OnAfterOneTest.
    Set tOverride = ##class(SessionAgent.Agent.ProviderOverride).GetOverride()
    If $IsObject(tOverride) {
        Quit tOverride
    }

    Set tProvider = $$$NULLOREF
    If pConfig.Provider = "openai" {
        Set tProvider = ##class(SessionAgent.LLM.OpenAIProvider).%New()
    }
    ; Stories 5.1 / 5.2 / 5.3 will extend this switch with anthropic /
    ; gemini / openai-compatible. Unknown values fall through to NULLOREF
    ; so RunTurn surfaces the "Unsupported provider" envelope.
    Quit tProvider
}

/// <p>Internal — read the persisted <property>TurnsJson</property> stream
/// into an in-memory <CLASS>%DynamicArray</CLASS>. Empty / unset stream
/// returns a fresh empty array.</p>
ClassMethod LoadTurns(pHist As SessionAgent.Chat.History) As %DynamicArray [ Internal ]
{
    Set tArr = ##class(%DynamicArray).%New()
    If '$IsObject(pHist) Quit tArr
    If '$IsObject(pHist.TurnsJson) Quit tArr
    Do pHist.TurnsJson.Rewind()
    If pHist.TurnsJson.AtEnd Quit tArr
    Set tBuf = ""
    While 'pHist.TurnsJson.AtEnd {
        Set tBuf = tBuf _ pHist.TurnsJson.Read(32000)
    }
    If tBuf = "" Quit tArr
    Try {
        Set tArr = ##class(%DynamicArray).%FromJSON(tBuf)
    }
    Catch ex {
        ; Corrupt history JSON — start fresh rather than crash. The
        ; next %Save will overwrite the corrupt stream with valid JSON.
        Set tArr = ##class(%DynamicArray).%New()
    }
    Quit tArr
}

/// <p>Internal — write the in-memory turns array back to the persisted
/// <property>TurnsJson</property> stream. Clears any prior content
/// before writing so the stream always reflects the canonical
/// turns array, never appended garbage.</p>
ClassMethod StoreTurns(pHist As SessionAgent.Chat.History, pTurns As %DynamicArray) [ Internal ]
{
    If '$IsObject(pHist) Quit
    If '$IsObject(pTurns) Quit
    Do pHist.TurnsJson.Clear()
    Do pTurns.%ToJSON(pHist.TurnsJson)
    Quit
}

/// <p>Internal — append a synthetic assistant text turn to the in-memory
/// turns array. Used for terminal envelopes that don't come from the
/// provider (max-iter cap, unsupported provider, hard error).</p>
ClassMethod AppendAssistantText(pTurns As %DynamicArray, pText As %String) [ Internal ]
{
    Set tTurn = ##class(%DynamicObject).%New()
    Do tTurn.%Set("role", "assistant")
    Set tContent = ##class(%DynamicArray).%New()
    Set tBlock = ##class(%DynamicObject).%New()
    Do tBlock.%Set("type", "text")
    Do tBlock.%Set("text", pText)
    Do tContent.%Push(tBlock)
    Do tTurn.%Set("content", tContent)
    Do pTurns.%Push(tTurn)
    Quit
}

/// <p>Internal — extract the joined plain-text from an assistant
/// content array. Concatenates the <code>text</code> field of every
/// <code>{type:"text"}</code> block; ignores
/// <code>{type:"tool_use"}</code> blocks (those don't carry display
/// text). Returns the empty string if no text blocks exist.</p>
ClassMethod ExtractAssistantText(pContent As %DynamicArray) As %String [ Internal ]
{
    Set tBuf = ""
    If '$IsObject(pContent) Quit tBuf
    Set tIter = pContent.%GetIterator()
    While tIter.%GetNext(.tIdx, .tBlock) {
        If '$IsObject(tBlock) Continue
        If tBlock.%Get("type") '= "text" Continue
        Set tBuf = tBuf _ tBlock.%Get("text")
    }
    Quit tBuf
}

/// <p>Internal — accumulate one provider call's
/// <CLASS>SessionAgent.Agent.ProviderResponse.Usage</CLASS> object into
/// the turn-level rollup carried on
/// <CLASS>SessionAgent.Agent.TurnResult.UsageRollup</CLASS>. Sums the
/// four canonical token-accounting keys
/// (<code>input_tokens</code>, <code>output_tokens</code>,
/// <code>cache_creation_input_tokens</code>,
/// <code>cache_read_input_tokens</code>); missing keys default to
/// <code>0</code>.</p>
ClassMethod RollupUsage(pRollup As %DynamicObject, pCallUsage As %DynamicObject) [ Internal ]
{
    If '$IsObject(pRollup) Quit
    If '$IsObject(pCallUsage) Quit
    Set tKeys = $ListBuild("input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")
    Set tPtr = 0
    While $ListNext(tKeys, tPtr, tKey) {
        Set tCurrent = 0
        If pRollup.%IsDefined(tKey) {
            Set tCurrent = +pRollup.%Get(tKey)
        }
        Set tDelta = 0
        If pCallUsage.%IsDefined(tKey) {
            Set tDelta = +pCallUsage.%Get(tKey)
        }
        Do pRollup.%Set(tKey, tCurrent + tDelta, "number")
    }
    Quit
}

/// <p>Internal — release the per-row exclusive lock on the chat-history
/// OREF by calling <method>%Save</method>. <method>%Save</method> is
/// preferred over <method>%Close</method> because the AgentLoop has
/// mutated the in-memory turns array and we want the persisted stream
/// to reflect those mutations. Failures are best-effort — the lock is
/// released either way once the OREF is dereferenced.</p>
ClassMethod ReleaseChatHistory(pHist As SessionAgent.Chat.History) [ Internal ]
{
    If '$IsObject(pHist) Quit
    Try {
        Set tSC = pHist.%Save()
        ; Best effort — if the save failed, the OREF dereference at the
        ; caller's argumentless quit will release the lock anyway.
        ; We do not surface tSC to the operator because the AgentLoop's
        ; never-throw contract (FR37) is the higher invariant.
    }
    Catch ex {
        ; Swallow — same rationale.
    }
    Quit
}

}
