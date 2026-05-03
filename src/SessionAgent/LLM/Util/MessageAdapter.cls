/// <p>Canonical-to-provider and provider-to-canonical message-history
/// adapter for the SessionAgent LLM layer. The canonical wire shape IS
/// the Anthropic Messages API shape; this class translates that shape
/// into / out of the OpenAI Chat Completions, Gemini generateContent,
/// and OpenAI-compatible (passthrough of OpenAI) wire shapes.</p>
///
/// <p><b>Canonical (Anthropic) message shape:</b></p>
/// <pre>
/// {role: "user"|"assistant"|"tool", content: [&lt;block&gt;...]}
///   where &lt;block&gt; is one of:
///     {type: "text", text: "..."}
///     {type: "tool_use", id: "...", name: "...", input: {...}}
///     {type: "tool_result", tool_use_id: "...", content: "..."|[{type:text,text:...}]}
/// </pre>
///
/// <p><b>Anthropic.</b> Passthrough — the canonical IS Anthropic. Both
/// directions return the input unchanged. Documented as an explicit
/// switch case so future contributors do not assume it is missing.</p>
///
/// <p><b>OpenAI.</b> Flatten the canonical content blocks into the OpenAI
/// Chat Completions message shape: <code>{role, content}</code> for plain
/// text-only assistant / user messages; assistant messages with tool_use
/// blocks become <code>{role:"assistant", content:null,
/// tool_calls:[{id, type:"function", function:{name, arguments:&lt;stringified
/// JSON&gt;}}]}</code>; canonical <code>tool</code>-role messages with
/// tool_result blocks become <code>{role:"tool", tool_call_id, content:
/// &lt;stringified JSON or text&gt;}</code> — one OpenAI message per
/// canonical tool_result block (OpenAI requires a separate tool message
/// per tool_call_id, while canonical packs multiple results in one
/// content array).</p>
///
/// <p><b>OpenAI tool_calls.arguments is a STRING.</b> The OpenAI Chat
/// Completions API specifies <code>function.arguments</code> as a
/// stringified JSON value (not an object). This adapter calls
/// <code>%ToJSON</code> on the canonical <code>tool_use.input</code>
/// object to produce the string form. The reverse (provider-to-canonical)
/// calls <code>%FromJSON</code> on the string to recover the object.
/// This stringification round-trip is the most-likely source of
/// adapter bugs, and the dedicated round-trip tests in
/// <CLASS>SessionAgent.Test.MessageAdapterTest</CLASS> lock the
/// invariant.</p>
///
/// <p><b>Gemini.</b> Convert to <code>{role: "user"|"model",
/// parts: [&lt;part&gt;]}</code> shape. Map roles:
/// <code>assistant</code>→<code>model</code>; <code>tool</code>→
/// <code>user</code> (Gemini does not have a separate tool role; tool
/// responses go in <code>user</code>-role parts as
/// <code>functionResponse</code>). Map block types:
/// <code>text</code>→<code>{text}</code>;
/// <code>tool_use</code>→<code>{functionCall:{name, args}}</code>;
/// <code>tool_result</code>→<code>{functionResponse:{name, response}}</code>
/// (the function name comes from the canonical tool_use that produced the
/// <code>tool_use_id</code>; v1 stores the id as the name when the
/// upstream name is unavailable — see the round-trip test for the
/// expected shape).</p>
///
/// <p><b>OpenAI-compatible.</b> Same as <code>openai</code> for both
/// directions. The two share a wire shape; the difference lives in the
/// concrete provider's HTTP base URL.</p>
///
/// <p><b>Unknown providers.</b> Both methods return the input unchanged
/// (passthrough) when <var>pProviderName</var> matches none of the four
/// known values. This avoids throwing in the LLM hot path; the AgentLoop
/// will surface the unknown-provider problem upstream when the actual
/// HTTP send fails.</p>
///
/// <p><b>References.</b></p>
/// <ul>
/// <li><a href="../../../../_bmad-output/planning-artifacts/epics.md">epics.md
/// Story 2.8</a> AC-2 — adapter contract.</li>
/// <li>Anthropic Messages API: https://docs.anthropic.com/claude/reference/messages_post
/// (canonical shape).</li>
/// <li>OpenAI Chat Completions: https://platform.openai.com/docs/api-reference/chat
/// (tool_calls.arguments is a string).</li>
/// <li>Gemini generateContent: https://ai.google.dev/api/rest/v1beta/models/generateContent
/// (parts + role mapping).</li>
/// </ul>
Class SessionAgent.LLM.Util.MessageAdapter Extends %RegisteredObject
{

/// <p>Canonical-shape provider name constants. Keep these in sync with
/// <property>SessionAgent.Config.Agent.Provider</property> values and the
/// <CLASS>SessionAgent.Audit.LlmCall</CLASS> Provider dimension.</p>
Parameter PROVIDERANTHROPIC = "anthropic";

Parameter PROVIDEROPENAI = "openai";

Parameter PROVIDERGEMINI = "gemini";

Parameter PROVIDEROPENAICOMPAT = "openai-compatible";

/// <p>Translate the canonical Anthropic-shape history into the named
/// provider's wire shape. Returns a fresh <CLASS>%DynamicArray</CLASS>;
/// the input is never mutated.</p>
///
/// <p>Provider dispatch:</p>
/// <ul>
/// <li><b>anthropic</b> — passthrough (canonical IS Anthropic).</li>
/// <li><b>openai</b> / <b>openai-compatible</b> — flatten to OpenAI Chat
/// Completions shape; tool_use blocks fold into
/// <code>tool_calls</code>; tool messages emit one OpenAI message per
/// tool_result block.</li>
/// <li><b>gemini</b> — convert to <code>{role, parts}</code> shape;
/// <code>assistant</code>→<code>model</code>;
/// <code>tool</code>→<code>user</code> with
/// <code>functionResponse</code> parts.</li>
/// <li>Unknown — passthrough.</li>
/// </ul>
ClassMethod CanonicalToProvider(pProviderName As %String, pCanonicalHistory As %DynamicArray) As %DynamicArray
{
    If '$IsObject(pCanonicalHistory) {
        Quit ##class(%DynamicArray).%New()
    }

    If pProviderName = ..#PROVIDERANTHROPIC {
        Quit pCanonicalHistory
    }
    If (pProviderName = ..#PROVIDEROPENAI) || (pProviderName = ..#PROVIDEROPENAICOMPAT) {
        Quit ..CanonicalToOpenAi(pCanonicalHistory)
    }
    If pProviderName = ..#PROVIDERGEMINI {
        Quit ..CanonicalToGemini(pCanonicalHistory)
    }

    ; Unknown provider — passthrough.
    Quit pCanonicalHistory
}

/// <p>Translate the named provider's raw response object into the
/// canonical Anthropic-shape <CLASS>%DynamicObject</CLASS>:
/// <code>{role:"assistant", content:[...], stopReason, usage}</code>.</p>
///
/// <p>Provider dispatch (same set as <method>CanonicalToProvider</method>);
/// see class doc-comment for the canonical block-type list.</p>
ClassMethod ProviderToCanonical(pProviderName As %String, pProviderResponseRaw As %DynamicObject) As %DynamicObject
{
    If '$IsObject(pProviderResponseRaw) {
        Set tEmpty = ##class(%DynamicObject).%New()
        Do tEmpty.%Set("role", "assistant")
        Do tEmpty.%Set("content", ##class(%DynamicArray).%New())
        Do tEmpty.%Set("stopReason", "")
        Do tEmpty.%Set("usage", ##class(%DynamicObject).%New())
        Quit tEmpty
    }

    If pProviderName = ..#PROVIDERANTHROPIC {
        Quit pProviderResponseRaw
    }
    If (pProviderName = ..#PROVIDEROPENAI) || (pProviderName = ..#PROVIDEROPENAICOMPAT) {
        Quit ..OpenAiToCanonical(pProviderResponseRaw)
    }
    If pProviderName = ..#PROVIDERGEMINI {
        Quit ..GeminiToCanonical(pProviderResponseRaw)
    }

    Quit pProviderResponseRaw
}

/// <p>Internal — canonical → OpenAI Chat Completions message array.</p>
///
/// <p>Per-message rules:</p>
/// <ul>
/// <li><b>user</b> with text-only blocks → <code>{role:"user",
/// content:&lt;concatenated text&gt;}</code>.</li>
/// <li><b>user</b> with mixed blocks (rare) → preserve text as content,
/// drop other block types (OpenAI user messages do not host
/// tool_use / tool_result).</li>
/// <li><b>assistant</b> text-only → <code>{role:"assistant",
/// content:&lt;text&gt;}</code>.</li>
/// <li><b>assistant</b> with tool_use blocks →
/// <code>{role:"assistant", content:&lt;text or null&gt;,
/// tool_calls:[{id, type:"function", function:{name,
/// arguments:&lt;stringified JSON&gt;}}]}</code>.</li>
/// <li><b>tool</b> with tool_result blocks → emit one OpenAI message
/// per block: <code>{role:"tool", tool_call_id, content:&lt;stringified
/// JSON or text&gt;}</code>.</li>
/// </ul>
ClassMethod CanonicalToOpenAi(pCanonical As %DynamicArray) As %DynamicArray [ Internal ]
{
    Set tOut = ##class(%DynamicArray).%New()

    Set tIter = pCanonical.%GetIterator()
    While tIter.%GetNext(.tIdx, .tMsg) {
        If '$IsObject(tMsg) Continue
        Set tRole = ""
        If tMsg.%IsDefined("role") {
            Set tRole = tMsg.%Get("role")
        }
        Set tContent = $$$NULLOREF
        If tMsg.%IsDefined("content") {
            Set tContent = tMsg.%Get("content")
        }

        ; Tool role: emit one openai "tool" message per tool_result block.
        If tRole = "tool" {
            If $IsObject(tContent) {
                Set tToolIter = tContent.%GetIterator()
                While tToolIter.%GetNext(.tBidx, .tBlock) {
                    If '$IsObject(tBlock) Continue
                    If 'tBlock.%IsDefined("type") Continue
                    If tBlock.%Get("type") '= "tool_result" Continue
                    Set tToolMsg = ##class(%DynamicObject).%New()
                    Do tToolMsg.%Set("role", "tool")
                    If tBlock.%IsDefined("tool_use_id") {
                        Do tToolMsg.%Set("tool_call_id", tBlock.%Get("tool_use_id"))
                    }
                    ; tool_result.content can be a string or an array of
                    ; {type:text, text:...} blocks. Stringify the array
                    ; form to JSON; pass strings through verbatim.
                    Set tResultContent = ""
                    If tBlock.%IsDefined("content") {
                        Set tRC = tBlock.%Get("content")
                        If $IsObject(tRC) {
                            Set tResultContent = tRC.%ToJSON()
                        } Else {
                            Set tResultContent = tRC
                        }
                    }
                    Do tToolMsg.%Set("content", tResultContent)
                    Do tOut.%Push(tToolMsg)
                }
            }
            Continue
        }

        ; user / assistant / other — flatten content blocks.
        Set tTextParts = ""
        Set tToolCalls = ##class(%DynamicArray).%New()
        Set tHasToolCalls = 0
        If $IsObject(tContent) {
            Set tBlockIter = tContent.%GetIterator()
            While tBlockIter.%GetNext(.tBidx, .tBlock) {
                If '$IsObject(tBlock) Continue
                If 'tBlock.%IsDefined("type") Continue
                Set tType = tBlock.%Get("type")
                If tType = "text" {
                    If tBlock.%IsDefined("text") {
                        If tTextParts '= "" {
                            ; ObjectScript double-quoted strings do NOT
                            ; interpret backslash escapes — use $Char(10)
                            ; for a real newline between concatenated text
                            ; blocks (the OpenAI content field is a single
                            ; string, so blocks must be joined with a
                            ; user-visible separator).
                            Set tTextParts = tTextParts _ $Char(10)
                        }
                        Set tTextParts = tTextParts _ tBlock.%Get("text")
                    }
                } ElseIf tType = "tool_use" {
                    Set tHasToolCalls = 1
                    Set tToolCall = ##class(%DynamicObject).%New()
                    If tBlock.%IsDefined("id") {
                        Do tToolCall.%Set("id", tBlock.%Get("id"))
                    }
                    Do tToolCall.%Set("type", "function")
                    Set tFn = ##class(%DynamicObject).%New()
                    If tBlock.%IsDefined("name") {
                        Do tFn.%Set("name", tBlock.%Get("name"))
                    }
                    ; Stringify the input object — OpenAI requires a string.
                    Set tArgsStr = "{}"
                    If tBlock.%IsDefined("input") {
                        Set tInput = tBlock.%Get("input")
                        If $IsObject(tInput) {
                            Set tArgsStr = tInput.%ToJSON()
                        } ElseIf tInput '= "" {
                            Set tArgsStr = tInput
                        }
                    }
                    Do tFn.%Set("arguments", tArgsStr)
                    Do tToolCall.%Set("function", tFn)
                    Do tToolCalls.%Push(tToolCall)
                }
                ; Skip unknown block types — never throw on the LLM hot path.
            }
        } ElseIf tContent '= "" {
            ; content is a bare string — pass through.
            Set tTextParts = tContent
        }

        Set tOaMsg = ##class(%DynamicObject).%New()
        Do tOaMsg.%Set("role", tRole)
        ; OpenAI requires content. If we have text, set it; else use
        ; empty string (representing null content with tool_calls).
        Do tOaMsg.%Set("content", tTextParts)
        If tHasToolCalls && (tRole = "assistant") {
            Do tOaMsg.%Set("tool_calls", tToolCalls)
        }
        Do tOut.%Push(tOaMsg)
    }

    Quit tOut
}

/// <p>Internal — OpenAI Chat Completions response object → canonical
/// Anthropic-shape <CLASS>%DynamicObject</CLASS>.</p>
///
/// <p>Reads <code>choices[0].message.content</code> (string → wrap in a
/// single text block); reads <code>choices[0].message.tool_calls[]</code>
/// → array of <code>{type:"tool_use", id, name, input:&lt;parsed
/// JSON&gt;}</code> blocks. Maps <code>finish_reason</code> →
/// <code>stopReason</code> (<code>tool_calls</code>→<code>tool_use</code>;
/// <code>stop</code>→<code>end_turn</code>; pass-through otherwise).
/// Maps <code>usage.prompt_tokens</code> → <code>input_tokens</code>;
/// <code>usage.completion_tokens</code> → <code>output_tokens</code>.</p>
ClassMethod OpenAiToCanonical(pRaw As %DynamicObject) As %DynamicObject [ Internal ]
{
    Set tOut = ##class(%DynamicObject).%New()
    Do tOut.%Set("role", "assistant")

    Set tContent = ##class(%DynamicArray).%New()
    Set tStopReason = ""

    If pRaw.%IsDefined("choices") {
        Set tChoices = pRaw.%Get("choices")
        If $IsObject(tChoices) && (tChoices.%Size() > 0) {
            Set tChoice0 = tChoices.%Get(0)
            If $IsObject(tChoice0) {
                If tChoice0.%IsDefined("finish_reason") {
                    Set tFinish = tChoice0.%Get("finish_reason")
                    Set tStopReason = ..MapOpenAiFinishReason(tFinish)
                }
                If tChoice0.%IsDefined("message") {
                    Set tMsg = tChoice0.%Get("message")
                    If $IsObject(tMsg) {
                        ; Text content.
                        If tMsg.%IsDefined("content") {
                            Set tMsgContent = tMsg.%Get("content")
                            If (tMsgContent '= "") && ($IsObject(tMsgContent) = 0) {
                                Set tTextBlock = ##class(%DynamicObject).%New()
                                Do tTextBlock.%Set("type", "text")
                                Do tTextBlock.%Set("text", tMsgContent)
                                Do tContent.%Push(tTextBlock)
                            }
                        }
                        ; tool_calls → tool_use blocks.
                        If tMsg.%IsDefined("tool_calls") {
                            Set tCalls = tMsg.%Get("tool_calls")
                            If $IsObject(tCalls) {
                                Set tCallIter = tCalls.%GetIterator()
                                While tCallIter.%GetNext(.tCidx, .tCall) {
                                    If '$IsObject(tCall) Continue
                                    Set tBlock = ##class(%DynamicObject).%New()
                                    Do tBlock.%Set("type", "tool_use")
                                    If tCall.%IsDefined("id") {
                                        Do tBlock.%Set("id", tCall.%Get("id"))
                                    }
                                    If tCall.%IsDefined("function") {
                                        Set tFn = tCall.%Get("function")
                                        If $IsObject(tFn) {
                                            If tFn.%IsDefined("name") {
                                                Do tBlock.%Set("name", tFn.%Get("name"))
                                            }
                                            ; arguments is a string — parse back to object.
                                            Set tInputObj = ##class(%DynamicObject).%New()
                                            If tFn.%IsDefined("arguments") {
                                                Set tArgsStr = tFn.%Get("arguments")
                                                If tArgsStr '= "" {
                                                    Try {
                                                        Set tInputObj = ##class(%DynamicObject).%FromJSON(tArgsStr)
                                                    } Catch ex {
                                                        ; Malformed args — emit empty object;
                                                        ; never throw on the LLM hot path.
                                                        Set tInputObj = ##class(%DynamicObject).%New()
                                                    }
                                                }
                                            }
                                            Do tBlock.%Set("input", tInputObj)
                                        }
                                    }
                                    Do tContent.%Push(tBlock)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Do tOut.%Set("content", tContent)
    Do tOut.%Set("stopReason", tStopReason)

    ; Usage mapping.
    Set tUsage = ##class(%DynamicObject).%New()
    Do tUsage.%Set("input_tokens", 0)
    Do tUsage.%Set("output_tokens", 0)
    Do tUsage.%Set("cache_creation_input_tokens", 0)
    Do tUsage.%Set("cache_read_input_tokens", 0)
    If pRaw.%IsDefined("usage") {
        Set tRawUsage = pRaw.%Get("usage")
        If $IsObject(tRawUsage) {
            If tRawUsage.%IsDefined("prompt_tokens") {
                Do tUsage.%Set("input_tokens", +tRawUsage.%Get("prompt_tokens"))
            }
            If tRawUsage.%IsDefined("completion_tokens") {
                Do tUsage.%Set("output_tokens", +tRawUsage.%Get("completion_tokens"))
            }
        }
    }
    Do tOut.%Set("usage", tUsage)

    Quit tOut
}

/// <p>Internal — map OpenAI <code>finish_reason</code> values to canonical
/// <code>stopReason</code> values. Unknown values pass through unchanged
/// so future OpenAI additions surface in audit logs as the OpenAI
/// nomenclature rather than being silently coerced.</p>
ClassMethod MapOpenAiFinishReason(pFinish As %String) As %String [ Internal ]
{
    If pFinish = "stop" Quit "end_turn"
    If pFinish = "length" Quit "max_tokens"
    If pFinish = "tool_calls" Quit "tool_use"
    If pFinish = "function_call" Quit "tool_use"
    If pFinish = "content_filter" Quit "stop_sequence"
    Quit pFinish
}

/// <p>Internal — canonical → Gemini generateContent message array.</p>
///
/// <p>Per-message: <code>{role, parts}</code> where role is
/// <code>user</code> or <code>model</code> (assistant→model;
/// tool→user); parts is an array of <code>{text}</code>,
/// <code>{functionCall:{name, args}}</code>, or
/// <code>{functionResponse:{name, response}}</code> elements. One Gemini
/// message per canonical message; multiple parts per message (Gemini
/// supports multi-part).</p>
ClassMethod CanonicalToGemini(pCanonical As %DynamicArray) As %DynamicArray [ Internal ]
{
    Set tOut = ##class(%DynamicArray).%New()

    Set tIter = pCanonical.%GetIterator()
    While tIter.%GetNext(.tIdx, .tMsg) {
        If '$IsObject(tMsg) Continue

        Set tCanonicalRole = ""
        If tMsg.%IsDefined("role") {
            Set tCanonicalRole = tMsg.%Get("role")
        }

        ; Role mapping. assistant→model; tool→user; user→user; default→user.
        Set tGeminiRole = "user"
        If tCanonicalRole = "assistant" {
            Set tGeminiRole = "model"
        } ElseIf tCanonicalRole = "tool" {
            Set tGeminiRole = "user"
        } ElseIf tCanonicalRole = "user" {
            Set tGeminiRole = "user"
        }

        Set tParts = ##class(%DynamicArray).%New()
        Set tContent = $$$NULLOREF
        If tMsg.%IsDefined("content") {
            Set tContent = tMsg.%Get("content")
        }

        If $IsObject(tContent) {
            Set tBlockIter = tContent.%GetIterator()
            While tBlockIter.%GetNext(.tBidx, .tBlock) {
                If '$IsObject(tBlock) Continue
                If 'tBlock.%IsDefined("type") Continue
                Set tType = tBlock.%Get("type")
                If tType = "text" {
                    If tBlock.%IsDefined("text") {
                        Set tPart = ##class(%DynamicObject).%New()
                        Do tPart.%Set("text", tBlock.%Get("text"))
                        Do tParts.%Push(tPart)
                    }
                } ElseIf tType = "tool_use" {
                    Set tFc = ##class(%DynamicObject).%New()
                    If tBlock.%IsDefined("name") {
                        Do tFc.%Set("name", tBlock.%Get("name"))
                    }
                    Set tArgs = ##class(%DynamicObject).%New()
                    If tBlock.%IsDefined("input") {
                        Set tInput = tBlock.%Get("input")
                        If $IsObject(tInput) {
                            Set tArgs = tInput
                        }
                    }
                    Do tFc.%Set("args", tArgs)
                    Set tPart = ##class(%DynamicObject).%New()
                    Do tPart.%Set("functionCall", tFc)
                    Do tParts.%Push(tPart)
                } ElseIf tType = "tool_result" {
                    Set tFr = ##class(%DynamicObject).%New()
                    ; Gemini wants a function name on functionResponse;
                    ; canonical tool_result carries tool_use_id but not
                    ; the original function name. v1 stores the id as the
                    ; name (the round-trip test locks this convention).
                    If tBlock.%IsDefined("tool_use_id") {
                        Do tFr.%Set("name", tBlock.%Get("tool_use_id"))
                    }
                    Set tResp = ##class(%DynamicObject).%New()
                    If tBlock.%IsDefined("content") {
                        Set tRC = tBlock.%Get("content")
                        If $IsObject(tRC) {
                            Do tResp.%Set("content", tRC)
                        } Else {
                            Do tResp.%Set("content", tRC)
                        }
                    }
                    Do tFr.%Set("response", tResp)
                    Set tPart = ##class(%DynamicObject).%New()
                    Do tPart.%Set("functionResponse", tFr)
                    Do tParts.%Push(tPart)
                }
            }
        } ElseIf tContent '= "" {
            Set tPart = ##class(%DynamicObject).%New()
            Do tPart.%Set("text", tContent)
            Do tParts.%Push(tPart)
        }

        Set tGmsg = ##class(%DynamicObject).%New()
        Do tGmsg.%Set("role", tGeminiRole)
        Do tGmsg.%Set("parts", tParts)
        Do tOut.%Push(tGmsg)
    }

    Quit tOut
}

/// <p>Internal — Gemini generateContent response → canonical
/// <CLASS>%DynamicObject</CLASS>.</p>
///
/// <p>Reads <code>candidates[0].content.parts[]</code> and remaps each:
/// <code>parts[].text</code>→<code>{type:text, text}</code>;
/// <code>parts[].functionCall</code>→<code>{type:tool_use, id, name,
/// input:args}</code> (id is auto-generated since Gemini does not
/// return one — sequential <code>gemini-call-N</code>). Maps
/// <code>candidates[0].finishReason</code> → canonical stopReason.
/// Maps <code>usageMetadata.promptTokenCount</code> →
/// <code>input_tokens</code>; <code>candidatesTokenCount</code> →
/// <code>output_tokens</code>.</p>
ClassMethod GeminiToCanonical(pRaw As %DynamicObject) As %DynamicObject [ Internal ]
{
    Set tOut = ##class(%DynamicObject).%New()
    Do tOut.%Set("role", "assistant")

    Set tContent = ##class(%DynamicArray).%New()
    Set tStopReason = ""
    Set tCallSeq = 0

    If pRaw.%IsDefined("candidates") {
        Set tCands = pRaw.%Get("candidates")
        If $IsObject(tCands) && (tCands.%Size() > 0) {
            Set tCand0 = tCands.%Get(0)
            If $IsObject(tCand0) {
                If tCand0.%IsDefined("finishReason") {
                    Set tFinish = tCand0.%Get("finishReason")
                    Set tStopReason = ..MapGeminiFinishReason(tFinish)
                }
                If tCand0.%IsDefined("content") {
                    Set tCContent = tCand0.%Get("content")
                    If $IsObject(tCContent) && tCContent.%IsDefined("parts") {
                        Set tParts = tCContent.%Get("parts")
                        If $IsObject(tParts) {
                            Set tPartIter = tParts.%GetIterator()
                            While tPartIter.%GetNext(.tPidx, .tPart) {
                                If '$IsObject(tPart) Continue
                                If tPart.%IsDefined("text") {
                                    Set tBlock = ##class(%DynamicObject).%New()
                                    Do tBlock.%Set("type", "text")
                                    Do tBlock.%Set("text", tPart.%Get("text"))
                                    Do tContent.%Push(tBlock)
                                } ElseIf tPart.%IsDefined("functionCall") {
                                    Set tFc = tPart.%Get("functionCall")
                                    If $IsObject(tFc) {
                                        Set tBlock = ##class(%DynamicObject).%New()
                                        Do tBlock.%Set("type", "tool_use")
                                        Set tCallSeq = tCallSeq + 1
                                        Do tBlock.%Set("id", "gemini-call-" _ tCallSeq)
                                        If tFc.%IsDefined("name") {
                                            Do tBlock.%Set("name", tFc.%Get("name"))
                                        }
                                        Set tArgs = ##class(%DynamicObject).%New()
                                        If tFc.%IsDefined("args") {
                                            Set tFcArgs = tFc.%Get("args")
                                            If $IsObject(tFcArgs) {
                                                Set tArgs = tFcArgs
                                            }
                                        }
                                        Do tBlock.%Set("input", tArgs)
                                        Do tContent.%Push(tBlock)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Do tOut.%Set("content", tContent)
    Do tOut.%Set("stopReason", tStopReason)

    ; Usage mapping.
    Set tUsage = ##class(%DynamicObject).%New()
    Do tUsage.%Set("input_tokens", 0)
    Do tUsage.%Set("output_tokens", 0)
    Do tUsage.%Set("cache_creation_input_tokens", 0)
    Do tUsage.%Set("cache_read_input_tokens", 0)
    If pRaw.%IsDefined("usageMetadata") {
        Set tRawUsage = pRaw.%Get("usageMetadata")
        If $IsObject(tRawUsage) {
            If tRawUsage.%IsDefined("promptTokenCount") {
                Do tUsage.%Set("input_tokens", +tRawUsage.%Get("promptTokenCount"))
            }
            If tRawUsage.%IsDefined("candidatesTokenCount") {
                Do tUsage.%Set("output_tokens", +tRawUsage.%Get("candidatesTokenCount"))
            }
        }
    }
    Do tOut.%Set("usage", tUsage)

    Quit tOut
}

/// <p>Internal — map Gemini <code>finishReason</code> values to canonical
/// <code>stopReason</code> values. Unknown values pass through.</p>
ClassMethod MapGeminiFinishReason(pFinish As %String) As %String [ Internal ]
{
    If pFinish = "STOP" Quit "end_turn"
    If pFinish = "MAX_TOKENS" Quit "max_tokens"
    If pFinish = "SAFETY" Quit "stop_sequence"
    If pFinish = "RECITATION" Quit "stop_sequence"
    If pFinish = "OTHER" Quit "stop_sequence"
    If pFinish = "TOOL_CALLS" Quit "tool_use"
    Quit pFinish
}

}
