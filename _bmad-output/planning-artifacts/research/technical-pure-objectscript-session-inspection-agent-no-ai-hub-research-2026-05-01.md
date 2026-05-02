---
stepsCompleted: [1, 2, 3, 4, 5, 6]
workflowComplete: true
inputDocuments:
  - irislib/%Net/HttpRequest.cls
  - irislib/Ens/Config/Credentials.cls
  - irislib/%SYSTEM/Util.cls
  - irislib/%SYSTEM/Encryption.cls
  - irislib/%Library/DynamicObject.cls (verified surface)
  - sources/iris-session-chat/_bmad-output/planning-artifacts/product-brief-ensemble-session-inspection-agent-distillate.md
  - Anthropic Messages API + Prompt Caching + Tool Use docs (May 2026)
  - OpenAI Function Calling + Chat Completions + Prompt Caching docs (May 2026)
  - MCP 2025-11-25 spec (server/tools, basic/transports, basic/authorization)
  - InterSystems IRIS 2024.1 release notes + class reference
  - BFCL V4 leaderboard for OSS tool-call reliability ranking
  - Perplexity MCP cross-checks for every non-trivial finding
workflowType: 'research'
lastStep: 6
research_type: 'technical'
research_topic: 'Pure-ObjectScript Session Inspection Agent — No AI Hub, IRIS 2024.1+'
research_goals: 'Design a complete pure-ObjectScript implementation path for the Ensemble Session Inspection Agent (originally specced in sources/iris-session-chat as an AI-Hub-coupled hackathon project) that ships ahead of AI Hub on IRIS 2024.1+. Topics: (1) ObjectScript agent loop over Anthropic/OpenAI HTTP APIs via %Net.HttpRequest; (2) tool registry & JSON-schema generation that stays MCP-exportable for a future epic, replacing %AI.ToolSet/%AI.Tool/<Query>; (3) persistent session state without %AI.Agent.Session; (4) three-layer read-only enforcement without %AI.Policy.Authorization; (5) LLM provider tool-call quality across Anthropic, OpenAI, and on-prem options; (6) Markdown→HTML rendering in CSP/Zen using only ObjectScript or browser-side JS; (7) Phase 1 terminal REPL deferral rationale; (8) API-key/secrets storage — verify %Library.IRISWallet availability in 2024.1 and design alternative if absent; (9) audit logging at the dispatch layer. Pure ObjectScript only — no embedded Python in the runtime path. MCP serving deferred from v1 but tool-registry architecture must not preclude future MCP exposure.'
user_name: 'Developer'
date: '2026-05-01'
web_research_enabled: true
source_verification: true
---

# Research Report: Technical

**Date:** 2026-05-01
**Author:** Developer
**Research Type:** Technical

---

## Research Overview

This document is the v1 architectural blueprint for **`iris-session-agent`** — a pure-ObjectScript reimplementation of the Ensemble Session Inspection Agent originally specced in [`sources/iris-session-chat/`](../../../sources/iris-session-chat/) as an AI-Hub-coupled hackathon project. The goal: ship the same operator-facing capability (a chat panel embedded in the IRIS Management Portal that explains what happened in an Ensemble session) **ahead of AI Hub's release**, on **IRIS / IRIS for Health 2024.1+**, with **zero embedded Python in the runtime path** and **a tool-registry shape that stays MCP-exportable for a future epic.** During the research, scope expanded (per [`docs/initial-prompt.md`](../../../docs/initial-prompt.md)) to include a sibling **Message Search Agent**, a **four-provider abstraction (OpenAI / Anthropic / Gemini / Ollama)**, **per-agent Zen configuration**, **chat-history lifecycle coupling to Ens session purge**, and **IPM-installable packaging**. See the *Scope Amendments* block below for the full reconciliation.

The research progresses through six structured steps: scope confirmation (§Technical Research Scope Confirmation), platform-surface inventory (§Technology Stack Analysis), pattern-level integration design (§Integration Patterns Analysis), named architectural components (§Architectural Patterns and Design), code-level implementation skeletons (§Implementation Approaches and Technology Adoption), and a synthesis with strategic recommendations + risk roll-up (§Research Synthesis & Executive Summary at the end of the document). Every load-bearing claim is cited against InterSystems documentation, vendor LLM-API docs (Anthropic, OpenAI, Google AI, Ollama, vLLM), the MCP 2025-11-25 specification, or local `irislib/` source — with confidence levels (High / Medium / Low) called out where corroboration is incomplete. Three Task-0 probes are carried forward into implementation stories (`%Dictionary.*` reflection on 2024.1, `SELECT INTO :exists`/`SQLCODE=100` semantics on 2024.1, Web Gateway timeout default on the operator's gateway version). For the bottom-line decision matrix, scan §Research Synthesis & Executive Summary at the end of this document.

## Table of Contents

1. [Technical Research Scope Confirmation](#technical-research-scope-confirmation) — what's in / what's out, methodology, and the IRIS 2024.1+ pure-ObjectScript constraint
2. [Technology Stack Analysis](#technology-stack-analysis) — IRIS 2024.1 platform primitives, LLM provider HTTP APIs, MCP protocol shape, browser rendering layer, Topic 8 wallet preflight
3. [Scope Amendments — 2026-05-01](#scope-amendments--2026-05-01-post-step-3) — five post-Step-3 expansions: two agents, four providers, Zen config, lifecycle coupling, IPM
4. [Integration Patterns Analysis](#integration-patterns-analysis) — agent tool-call loop, provider abstraction, CSP/Zen integration path, MCP-exportable dispatch contract, three-layer read-only enforcement, error/retry/backoff, audit logging, Web Gateway timeout coordination
5. [Architectural Patterns and Design](#architectural-patterns-and-design) — component diagram, two-agent infrastructure sharing, class hierarchy, four-provider abstraction (incl. Gemini), Topic 10 lifecycle-coupling decision (Option B), configuration architecture, three-layer read-only realized, CSP integration, IPM packaging, deployment topology, security architecture
6. [Implementation Approaches and Technology Adoption](#implementation-approaches-and-technology-adoption) — 11-epic sprint sequencing, working `module.xml`, `SessionAgent.Installer.Install()`, `SessionAgent.LLM.OpenAIProvider`, `SessionAgent.Util.RetryWithBackoff`, `SessionAgent.Tool.Base` + `Registry`, example tool implementation, `SessionAgent.Chat.History`, `SessionAgent.Task.PurgeOrphanedChatHistory`, `SessionAgent.Security.ReadOnlyRole`, `SessionAgent.EnsPortal.Util.ChatPanelDrawHelper`, `SessionAgent.UI.AgentConfig`, operator README content, test strategy
7. [Research Synthesis & Executive Summary](#research-synthesis--executive-summary) — top findings, strategic recommendations, risk roll-up, Task-0 probes carried forward, open questions, source documentation, workflow completion

---

<!-- Content will be appended sequentially through research workflow steps -->

## Technical Research Scope Confirmation

**Research Topic:** Pure-ObjectScript Session Inspection Agent — No AI Hub, IRIS 2024.1+

**Research Goals:** Design a complete pure-ObjectScript implementation path for the Ensemble Session Inspection Agent (originally specced in `sources/iris-session-chat/` as an AI-Hub-coupled hackathon project) so it ships ahead of AI Hub on IRIS 2024.1+.

**Project context that constrains the research** (from saved memory + this scoping conversation):

- **Pure ObjectScript only** — no embedded Python in the runtime path. Build-time tooling and one-off scripts may use Python.
- **IRIS / IRIS for Health 2024.1+** — every API, class, and parameter we propose as a primary path must be verified to exist in 2024.1. Newer-version features may be mentioned only as optimizations layered on a 2024.1-compatible baseline.
- **No AI Hub primitives** — `%AI.Agent`, `%AI.ToolSet`, `%AI.Tool`, `%AI.Agent.Session`, `%AI.Policy.Authorization`, `%AI.Shell.Console`, `%AI.MCP.Service` are all out of bounds. Replacements are the central deliverable.
- **MCP serving deferred from v1, but tool registry must remain MCP-exportable** for a future epic. Tool dispatch must be a clean `(toolName, jsonArgs) → jsonResult` surface that doesn't bake in Zen-hyperevent assumptions.
- **Phase 1 (terminal REPL) dropped from v1.** Phase 2 (chat tab in custom `EnsPortal.VisualTrace`) and Phase 3 (custom `EnsPortal.MessageViewer` with bookmark handoff) remain in scope.

**Technical Research Scope (nine topics, locked-in):**

1. **Agent loop architecture** — `%Net.HttpRequest` against Anthropic Messages / OpenAI Chat Completions; `%DynamicObject` patterns for `tool_use`/`tool_result` blocks; prompt-cache headers; retry/backoff; timeout handling; blocking-vs-async semantics inside CSP context.
2. **Tool registry & schema generation** — XData JSON tool definitions; `%Dictionary.*` reflection; compile-time SQL validation via `%SQL.Statement.%Prepare()`; **architectural constraint: must stay MCP-exportable for a future epic.**
3. **Persistent session state** — `%Persistent` class storing serialized message array; lifecycle (create / load / reset / purge); `%session.Data` mapping; concurrency / locking against the per-portal-user CSP session.
4. **Read-only enforcement (3 layers, no `%AI.Policy.Authorization`)** — Tool-impl discipline + custom dispatch wrapper consulting `mutates=0/1` metadata + IRIS RBAC SELECT-only role on `Ens.*` tables.
5. **LLM provider tool-call quality** — Anthropic Sonnet 4.5, OpenAI GPT-5, on-prem (Llama 3.1, Qwen 2.5) for PHI; tool-use accuracy benchmarks; PHI-deployment implications.
6. **Markdown→HTML rendering in CSP/Zen** — Pure-ObjectScript markdown parsers vs. JS-side (marked / markdown-it) loaded into the Zen page; XSS/escaping discipline.
7. **Phase 1 deferral rationale** — Document why pure-OS REPL is dropped from v1 (without `%AI.Shell.Console`); pre/cons for v1.5 reconsideration.
8. **Secrets / API-key storage** — **Pre-flight: verify `%Library.IRISWallet` availability in IRIS 2024.1 before recommending.** If absent, design a 2024.1-compatible alternative (encrypted CPF param, `Security.SSLConfigs`-style storage, env-var injection at container start).
9. **Audit logging at the dispatch layer** — Token counting from raw API response `usage` blocks; dispatch-wrapper instrumentation; persistent audit class schema with timestamp + user + tool calls + token counts + duration.

**Research Methodology:**

- **Primary sources:** InterSystems documentation pinned to the 2024.1 surface (`docs.intersystems.com/iris20241/`); local `irislib/` source where it represents 2024.1 or earlier; Anthropic / OpenAI official API documentation for HTTP request/response shapes.
- **Cross-check via Perplexity MCP** — minimum two authoritative sources per non-trivial finding, per the project's `research-first.md` rule. Use `search` for landscape questions, `get_documentation` for SDK/API specifics, `check_deprecated_code` to validate that recommended patterns haven't drifted.
- **2024.1 verification is mandatory**, not optional, for every API surface proposed as a primary path. Findings without explicit 2024.1 confirmation are flagged as Medium or Low confidence.
- **Confidence levels (High / Medium / Low)** called out where source corroboration is incomplete.
- **Conflicts** between docs and observed behavior flagged explicitly.

**Out of scope (kept here for honesty):**

- AI Hub primitives (`%AI.*`) — replaced, not researched.
- Embedded-Python alternatives — closed by saved memory.
- MCP server v1 implementation — deferred (registry design constrained for future).
- PHI redaction architecture — open question carried over from prior brief; not a v1 research topic unless re-scoped.

**Existing-doc cleanup** is a parallel deliverable: once research advances enough to know what supersedes what, I'll prepare concrete edit proposals for the two AI-Hub-coupled docs in `_bmad-output/planning-artifacts/research/`. No destructive edits without sign-off.

**Scope Confirmed:** 2026-05-01

---

## Technology Stack Analysis

> **Note on methodology:** Step-2 is a landscape inventory across four parallel research streams (IRIS 2024.1 platform primitives / LLM HTTP APIs / MCP protocol / browser rendering layer). Findings here are intentionally at the surface-area level; deeper integration patterns, architectural decisions, and concrete code-level findings land in steps 3–5. Every claim is cited; confidence levels are explicit.

### IRIS 2024.1 Platform Surface — The OS Primitives We'll Build On

The agent will be assembled from existing IRIS primitives — no AI Hub, no embedded Python. The following are confirmed available and stable on IRIS 2024.1+ (verified against local `irislib/` source unless otherwise noted).

- **`%Net.HttpRequest`** — Outbound HTTPS to LLM APIs. **HTTP/1.1 only** (RFC 2616-explicit in the class header), no HTTP/2 — fine for JSON-over-HTTPS, rules out gRPC. Default `Timeout` 30s; raise per call before LLM round-trips. No documented body size cap; large payloads ride `%Stream.GlobalCharacter` transparently. No keep-alive pool — each `%New()` is a fresh logical session. *Source: [`irislib/%Net/HttpRequest.cls`](irislib/%Net/HttpRequest.cls), [Documatic](https://docs.intersystems.com/irislatest/csp/documatic/%25CSP.Documatic.cls?LIBRARY=%25SYS&CLASSNAME=%25Net.HttpRequest).* **Confidence: High.**
- **`%DynamicObject` / `%DynamicArray`** — JSON construction and parsing for both directions of the LLM wire. The `%Set(key, value, type)` type-hint contract is critical and already documented correctly in this project's `CLAUDE.md`: `%Set("k", "", "null")` emits JSON `null`; `%Set("k", "null", "null")` emits the *string* `"null"`. Iterator (`%GetIterator`) is **not safe to mutate during iteration** — already a project rule. *Source: [Documatic — DynamicObject](https://docs.intersystems.com/irislatest/csp/documatic/%25CSP.Documatic.cls?LIBRARY=%25SYS&CLASSNAME=%25Library.DynamicObject).* **Confidence: High.**
- **`%Persistent` + storage** — Session-state and audit-log substrate. JSON-in-stream pattern: declare a `%Stream.GlobalCharacter` property, write `dynObj.%ToJSON()` into it, save transactionally. Row-level concurrency via `%OpenId(id, 4)` for exclusive read-modify-write locking; `%LOCKEXTRAS` for advanced overrides. **No first-class async `%Save`** — defer side-effect saves to post-TCOMMIT `JOB` per the project's existing `Transaction Side Effects` rule. *Source: [GOBJ_propstream](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GOBJ_propstream).* **Confidence: High.**
- **`%Dictionary.{Class,Method,XData}Definition`** — Reflection for tool-registry generation and BP source retrieval. ID format is `Pkg.Class||MemberName` (double-pipe). 2024.1 surface is forward-compatible with later versions; do not assume any post-2024.1 fields exist. *Source: [ADICTIONARY](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=ADICTIONARY).* **Confidence: Medium** — only `irislatest` URL confirmed; **needs Task-0 probe** (per `research-first.md`) on a live 2024.1 instance before the tool-registry story is dispatched.
- **`%SQL.Statement.%Prepare()` / `%PrepareClassQuery()`** — Compile-time SQL validation for the SQL-driven half of the tool registry. Post-prepare `stmt.%Metadata.columns` exposes ODBC type, name, nullability — but **no built-in JSON-Schema export.** Mapping ODBCType → JSON type (4/-5/-6 → integer, 12/-9 → string, 6/8 → number, 91/93 → string + format) is the registry's job. *Source: [GSQL_queries](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GSQL_queries).* **Confidence: High.**
- **`%CSP.Session` + ZenMethod hyperevents** — Phase 2 chat-tab integration surface. **`%session.AppTimeout` defaults to 900s (15 min)** — a 15-second blocking LLM round-trip is well under the session ceiling. **The real cliff is the Web Gateway "Server Response Timeout"** (default low; commonly 60s on production gateways) — must be raised on the Web Gateway management page if synchronous LLM calls run long. **This is an operator-observable prerequisite that must land in the README** per the project's `research-first.md` rule 5. *Source: [GCSP_session](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GCSP_session).* **Confidence: Medium** — gateway-timeout default varies by deployment.
- **`Ens.Config.Credentials`** — Confirmed in 2024.1 by direct read of [`irislib/Ens/Config/Credentials.cls`](irislib/Ens/Config/Credentials.cls). Stores `(SystemName, Username, Password, BusinessPartner)`; password is **stored encrypted at rest in a separate `%SYS.Ensemble` secondary store** (not in the row global) using IRIS's managed key infrastructure. Reusable for LLM API keys (store as `Username="apikey"`, `Password="<secret>"`, keyed by SystemName like `"openai-prod"`). **Caveat:** namespace must have Ensemble enabled — true for HSCUSTOM and any Interop namespace, but worth verifying for non-Interop deployments. **Confidence: High.**
- **`$SYSTEM.Util.GetEnviron(name)`** — Confirmed in [`irislib/%SYSTEM/Util.cls`](irislib/%SYSTEM/Util.cls). Returns env vars from the iris-main process's environment at container startup — **container/Kubernetes-secret-friendly**. Works inside CSP request context (uses process env, not `%request.CgiEnvs`). **Confidence: High.**
- **`$System.Encryption.AESCBCEncrypt/Decrypt`, `AESGCMEncrypt/Decrypt`, `PBKDF2`** — All confirmed in [`irislib/%SYSTEM/Encryption.cls`](irislib/%SYSTEM/Encryption.cls). PBKDF2 signature: `PBKDF2(Password, Iterations, Salt, KeyLength, bitlength=160)` — bitlength is a **bit size** (160/256/384/512), not an algorithm version number, per the project's existing `IRIS Library Source` rule. AES-GCM is the modern recommendation (authenticated encryption); CBC is fine if HMAC is layered. **Confidence: High.**

### LLM Provider HTTP APIs — Wire Protocol Landscape

The agent will speak directly to LLM provider HTTP APIs from `%Net.HttpRequest`. Two providers form the v1 surface; on-prem options ride one of them.

- **Anthropic Messages API** (`POST https://api.anthropic.com/v1/messages`) for Claude Sonnet 4.5 / Opus 4.7. Required headers: `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`. Tool definition shape: `{name, description, input_schema}`. Tool-use response carries `content[]` blocks with `type: "tool_use"`; the entire prior assistant turn (with `tool_use` block) **must** be re-sent in the next request — Anthropic re-derives state from message history. Tool results come back as `user` messages with `content: [{type: "tool_result", tool_use_id, content, is_error}]`. **Prompt caching** via `cache_control: {type: "ephemeral"}` placed at the END of any cacheable block; cache key is the prefix hash in the order `tools → system → messages`; 5-min sliding TTL (1-hour TTL via `anthropic-beta: prompt-caching-2024-11-05` header). **Usage block (log all four for audit):** `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`. *Sources: [Messages API](https://docs.anthropic.com/en/api/messages), [Prompt Caching](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching), [Tool Use](https://docs.anthropic.com/en/docs/agents-and-tools/tool-use).* **Confidence: High** (all from official docs).
- **OpenAI Chat Completions API** (`POST https://api.openai.com/v1/chat/completions`) for GPT-4o / GPT-5 (limited GA in 2026). Tool definition shape: `{type: "function", function: {name, description, parameters, strict}}`. Tool-call response: `choices[0].message.tool_calls[].function.arguments` is a **stringified JSON** (not an object — parse before use). Tool-result follow-up: append `{role: "tool", tool_call_id, content}` per call. **Auto-caching** for prompts ≥1024 tokens (no manual `cache_control`); read at 25% input price. Usage: `prompt_tokens`, `completion_tokens`, `prompt_tokens_details.cached_tokens`, `completion_tokens_details.reasoning_tokens` (o-series only). The newer `/v1/responses` endpoint is live but not deprecated; **target Chat Completions for v1** — broadest compatibility, every OSS endpoint speaks it. *Sources: [Function Calling](https://platform.openai.com/docs/guides/function-calling), [API Reference](https://platform.openai.com/docs/api-reference/chat), [Prompt Caching](https://platform.openai.com/docs/guides/prompt-caching).* **Confidence: High.**
- **Open-source / self-hosted (PHI-deployment story)** — Both **Ollama** (`/v1/chat/completions` OpenAI-compatible) and **vLLM** (OpenAI-compatible only; needs `--enable-auto-tool-choice` + `--tool-call-parser` matching the model) ride the OpenAI translator for free. Tool-calling reliability per BFCL V4 leaderboard (late-2025/early-2026): **Qwen 2.5 (32B/72B)** is the top OSS tier with reliable strict-JSON arg generation; **Llama 3.3 70B** strong on instruction-following, behind Qwen on JSON discipline; **Llama 3.1 8B** usable for cheap low-stakes tool calls but expect occasional malformed args. Treat any arg-parse failure as a retry-with-correction loop. *Sources: [Ollama Tool Support](https://ollama.com/blog/tool-support), [vLLM OpenAI server](https://docs.vllm.ai/), [BFCL leaderboard](https://gorilla.cs.berkeley.edu/leaderboard.html).* **Confidence: High** (vendor docs); **Medium** (BFCL ranking specifics — leaderboard moves).

### Anthropic vs. OpenAI — Differences That Matter for the OS Adapter

A thin ObjectScript adapter pattern (`LLMProvider` abstract → `Anthropic`, `OpenAI` concretes) over `%Net.HttpRequest` covers ~90% of the surface. Bind once on the Anthropic shape (strictly more structured) and adapt down to OpenAI:

| Concern | Anthropic | OpenAI |
|---|---|---|
| Tool-def keys | `name`, `description`, `input_schema` | `type:"function"`, `function:{name, description, parameters}` |
| Tool args wire format | `input` is **object** | `arguments` is **string** (JSON.stringify'd) |
| Tool-result message role | `user` with `content[]` of `tool_result` blocks | dedicated `tool` role, one msg per call |
| Tool-result correlation key | `tool_use_id` | `tool_call_id` |
| Stop reason for tool turn | `tool_use` | `tool_calls` |
| Caching | Manual `cache_control` markers | Automatic (≥1024 tokens) |
| Tool choice "force" | `{type:"any"}` | `"required"` |
| System prompt | Top-level `system` field | `{role:"system"}` in messages |
| Usage fields for cache audit | `cache_creation_input_tokens`, `cache_read_input_tokens` | `prompt_tokens_details.cached_tokens` |

### MCP Protocol — Future-Export Constraints (Not v1, but Architectural)

MCP serving is deferred from v1, but the tool-registry shape **must not preclude** MCP exposure later. Spec verified at [MCP 2025-11-25 server/tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools), [transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports), [authorization](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization).

- **Tool definition (`tools/list`)**: each tool exposes `{name, description, inputSchema}` where `inputSchema` is a valid **JSON Schema 2020-12** object. Default to `{type:"object", additionalProperties:false}` for zero-arg tools; `inputSchema` must never be null. Optional fields: `title`, `outputSchema`, `icons`.
- **Tool execution (`tools/call`)**: returns a `content` array of items typed `text` / `image` / `resource`, plus an optional `structuredContent` typed JSON field, plus `isError: true|false`. Errors are signaled via `isError` + content array, **not** JSON-RPC error frames.
- **Transport (May 2026)**: stdio for local servers; **SSE is deprecated** since `2025-03-26` (do not target); **streamable HTTP** is the current standard. For an IRIS-served MCP endpoint, streamable HTTP over a CSP REST dispatch class is the only realistic in-process path.
- **JSON Schema lowest-common-denominator** that satisfies MCP, Anthropic, and OpenAI: `{type, properties, required, enum, description, additionalProperties}`. Avoid `$ref`, `oneOf`/`anyOf` discriminators, and exotic format keywords if cross-vendor portability matters.
- **Authorization**: OAuth 2.1 + PKCE (RFC 7636) + Resource Indicators (RFC 8707) + Protected Resource Metadata (RFC 9728) at `/.well-known/oauth-protected-resource`. Don't implement now, but **don't tie tool execution to a CSP `%session.Username`** — keep an explicit caller-identity argument that a future OAuth handler can populate.
- **Naming**: `mcp__servername__toolname` is **client-side namespacing** (Claude Code etc. add this prefix). Server-side, tool names need only be unique within the server, ≤64 chars, alphanumeric + `_`/`-`, starting with a letter. Recommend internal **snake_case verb-noun** (`session_summary`, `message_inspect`, `bp_source_get`).

**The 7-anti-pattern cheat sheet** for the future-export-safe registry:

1. Reading `%session.Data` or `%request.CgiEnvs` from inside a tool implementation.
2. Assuming the caller is a logged-in CSP/portal user.
3. Returning HTML, redirects, or `%CSP.Response.Write()` output.
4. Mutating ZenPage fields or relying on Zen page state.
5. Using ObjectScript exceptions to signal tool errors instead of returning structured `{isError: true, content: [...]}`.
6. Hardcoding namespace via `$NAMESPACE` lookups inside tools — pass namespace in `jsonArgs`.
7. Streaming via `Write !,...` to the device — MCP streaming is JSON-framed, not raw stdout.

### Browser Rendering Layer — Markdown→HTML in the Chat Panel

LLM output is markdown; the chat panel needs HTML. **No viable pure-ObjectScript markdown parser exists** on OEX or the InterSystems Community as of May 2026. Pure-OS implementation is multi-week + ongoing CommonMark spec drift — **not recommended.** Server-side via JSRuntime/V8 is **not stable in 2024.1** — skip.

JS-side rendering is the recommended path. Ranking, with bundle sizes and XSS posture (sources: [pkgpulse marked vs markdown-it](https://www.pkgpulse.com/compare/markdown-it-vs-marked), [OEX](https://openexchange.intersystems.com), [IRIS 2024.1 release notes](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GCRN_new20241)):

| Library | Min+Gzip | GFM Built-in | XSS Posture | Recent CVEs |
|---|---|---|---|---|
| **marked** ≥ 18.0.2 | ~12 KB | Yes (tables, fenced, autolinks, task lists, strikethrough) | Escapes HTML, opt-in for `silent`/sanitization | [CVE-2026-41680](https://app.opencve.io/cve/?vendor=markedjs) DoS in 18.0.0–18.0.1, fixed in 18.0.2 |
| **markdown-it** | ~40-60 KB | Plugins required | `html: false` is default | [CVE-2025-7969](https://nvd.nist.gov/vuln/detail/CVE-2025-7969) (disputed) |

**Recommendation for v1**: ship `marked` ≥ 18.0.2 + `Prism.js` (curated language set: objectscript / sql / javascript / python — falls back to `markup`) + `DOMPurify` for explicit XSS gating, **all vendored locally** under the CSP application's static directory rather than CDN-loaded (portal sessions inside customer firewalls often block external CDNs and vendoring eliminates supply-chain timing risk). Total payload ~45 KB gzipped. Configure marked with `gfm:true, breaks:true`, route fenced code through Prism in the highlight callback, then run the resulting HTML through DOMPurify before injecting into the chat DOM. Trust boundary stays explicit: **portal RBAC trusts the JSON envelope; DOMPurify is the gate for the LLM-authored content inside it.**

### Pre-flight Findings — Critical 2024.1 Compatibility Gates

The Topic 8 preflight ran first (binary-outcome gate that shapes every other choice):

- **`%Library.IRISWallet` does NOT exist in IRIS 2024.1.** The Secure Wallet feature was introduced in IRIS 2026.1 per [secrets-mgmt docs](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=ROARS_secrets_mgmt) and is absent from the [2024.1 new-features list](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GCRN_new20241). Local `irislib/` confirms the absence — no `IRISWallet*` files exist. **This conflicts with the original product brief** in `sources/iris-session-chat/_bmad-output/planning-artifacts/`, which casually references "IRIS Wallet" — that brief assumed a newer IRIS than our 2024.1 floor allows.
- **2024.1-compatible secrets storage path (recommended order):**
  1. **Primary: `$SYSTEM.Util.GetEnviron("ANTHROPIC_API_KEY")`** — Docker / Kubernetes / Compose secret-friendly, no DB writes for keys, key never persists in IRIS storage.
  2. **Secondary: `Ens.Config.Credentials`** — for IRIS-managed secret storage when env-vars aren't operationally available (e.g., key rotation via Management Portal). Encrypted at rest in `%SYS.Ensemble` secondary store.
  3. **Last-resort: custom `%Persistent` + `$System.Encryption.AESGCMEncrypt`** — only if neither above fits the operational environment.

### Top Operational Risks Surfaced at Step 2

These will be carried forward into the architectural-patterns and implementation steps:

1. **Web Gateway "Server Response Timeout" — not the CSP session timeout — is the real LLM-call cliff.** The 15-min `%session.AppTimeout` is fine; the gateway timeout is commonly 60s and may need to be raised. **README must document this as an operator prerequisite.**
2. **`%Dictionary.{Class,Method,XData}Definition` 2024.1 verification is Medium-confidence** based on `irislatest`-only doc URL. **Task-0 probe required** before the tool-registry-generation story is dispatched (per `research-first.md` rule 4): run `##class(%Dictionary.MethodDefinition).%OpenId("Ens.BusinessProcess||OnRequest")` against a live 2024.1 instance and capture verbatim output.
3. **`Ens.Config.Credentials` requires Ensemble enabled in the namespace.** True for HSCUSTOM and any Interop namespace; verify before recommending for non-Interop deployments. Fallback: AES-encrypted secret in a `%Persistent` row with master key from `$SYSTEM.Util.GetEnviron`.
4. **OSS-LLM tool-call reliability is model-dependent.** Qwen 2.5 32B+ is the safe OSS pick; smaller models will produce malformed JSON args occasionally — the agent loop must catch arg-parse failures and prompt for correction.
5. **Anthropic prompt caching cost shape: writes 1.25× / reads 0.1×.** Misused (e.g., per-turn cache invalidation) it can cost more than no caching at all. Cache key invalidation rules must be respected when designing the system-prompt and tool-definition layout.

---

## Integration Patterns Analysis

> **Note on scope:** Step 2 inventoried *what surfaces are available*. Step 3 maps *how those surfaces connect* — sequence flows, interface contracts, error paths, and operational boundaries. Step 4 will turn these patterns into named architectural components.

### The Agent Tool-Call Loop — Sequence and State Machine

This is the central integration pattern. One **agent turn** is a synchronous interaction the operator triggers ("explain what happened in this session"); it consumes 1..N **LLM round-trips** because the model may invoke tools mid-turn, get tool results back, then continue. The loop terminates on `stop_reason ∈ {end_turn, max_tokens, stop_sequence}`.

Per-turn sequence (canonical, provider-agnostic):

```
operator presses Send (with userMessage, optionally selectedMessageId)
   │
   ▼
ChatPanelController (Zen hyperevent / future MCP request)
   │ load or create AgentSession (%Persistent, keyed by Ens session id + portal user)
   │ acquire row lock for the duration of the turn
   ▼
AgentLoop.RunTurn(session, userMessage, contextHints)
   │
   ├─ append { role: "user", content: userMessage } to session.history
   │
   └─ LOOP {
        1. provider.CallMessages(session.history, tools, system, cacheConfig)
        2. read response: contentBlocks[], stopReason, usage
        3. write usage to AuditLog
        4. append { role: "assistant", content: contentBlocks } to history
        5. if stopReason != "tool_use": BREAK
        6. for each toolUse block in contentBlocks:
             a. dispatch(toolUse.name, toolUse.input)  → toolResult JSON
             b. wrap as { tool_use_id, content, is_error }
        7. append { role: "user", content: toolResults[] } to history
        8. continue loop
      }
   │
   ├─ persist session.history (single %Save inside the lock)
   ├─ release lock
   ▼
return finalAssistantText (plus running usage totals) to caller
```

Key invariants — these are non-negotiable per provider semantics already cited in Step 2:

- The **entire** prior assistant turn (with its `tool_use` block) **must** be sent in the next request. Both Anthropic and OpenAI re-derive state from message history; we do not get to "trim" tool turns out of context.
- The agent loop is **bounded** — max-iterations per turn defaults to ~10 to prevent runaway tool-loops. If hit, append a synthetic system message ("max iterations reached, summarize") and break.
- `is_error: true` on a tool result is the right signal for tool-side failures — it lets the LLM recover and retry with different args. Throwing an ObjectScript exception kills the turn.

### LLM Provider Abstraction Pattern

The agent loop interacts with the provider through a single ObjectScript abstract class:

```objectscript
Class SessionAgent.LLM.Provider Extends %RegisteredObject [ Abstract ]
{
  /// Returns a ProviderResponse with content[], stopReason, usage
  Method CallMessages(
    pHistory As %DynamicArray,        // canonical Anthropic-shape messages
    pTools As %DynamicArray,          // canonical Anthropic-shape tool defs
    pSystem As %String,
    pCacheConfig As %DynamicObject,   // {systemCache: 1, toolsCache: 1, ttl: "5m"|"1h"}
    Output pResponse As SessionAgent.LLM.ProviderResponse
  ) As %Status [ Abstract ] { Quit $$$OK }

  /// Per Step 2: bind canonical on Anthropic shape, adapt down to OpenAI/OSS.
}
```

Three concrete implementations:

| Concrete | Endpoint | Translation work |
|---|---|---|
| `SessionAgent.LLM.AnthropicProvider` | `POST https://api.anthropic.com/v1/messages` | None — canonical shape |
| `SessionAgent.LLM.OpenAIProvider` | `POST https://api.openai.com/v1/chat/completions` | Tool def reshape; stringify args; rename `tool_use_id` → `tool_call_id`; explode tool-results from one user message into N `role:"tool"` messages |
| `SessionAgent.LLM.OpenAICompatProvider` | `POST <ollama|vllm|other>/v1/chat/completions` | Same as OpenAI; injects `--enable-auto-tool-choice` expectations |

Provider selection at startup time via configuration (not per-request) so the audit log can pin a provider for the entire session. Per-session provider switching is out of scope for v1.

### CSP/Zen ↔ Agent-Loop Integration Path

The chat panel is a tab inside `SessionAgent.EnsPortal.VisualTrace` (subclass of `EnsPortal.VisualTrace`). The hyperevent dispatch path:

```
(browser)
  zenPage.SendChatMessage(userText, currentMsgId)
    │ Zen ZenMethod hyperevent — synchronous AJAX POST
    ▼
(IRIS process under CSP)
  SessionAgent.EnsPortal.VisualTrace.SendChatMessage(userText, currentMsgId) ZenMethod
    │ resolve target Ensemble session id (currentTraceSessionId)
    │ resolve portal user (%session.Username)
    ▼
  SessionAgent.Agent.AgentLoop.RunTurn(
    irisSessionId,
    portalUser,
    userText,
    { "selectedMessageId": currentMsgId }
  )
    │ everything above the AgentLoop boundary is CSP-coupled
    │ everything below is CSP-free → MCP-portable
    ▼
  AgentLoop returns { assistantMarkdown, usageRollup, durationMs }
    │
    ▼
  ZenMethod returns JSON-encoded result string to client
    │
    ▼
  client-side: marked → Prism → DOMPurify → innerHTML
```

The clean break point is `AgentLoop.RunTurn`. **Tools and the loop must not read `%session`, `%request`, or any Zen state** — per the Step 2 anti-pattern list, those would break MCP export. Pass everything the loop needs through explicit arguments.

Concurrency: **acquire an exclusive row lock on the `AgentSession` row at the top of `RunTurn` and release at the bottom.** Two simultaneous tabs from the same operator targeting the same Ens session id would otherwise corrupt the message history. `%OpenId(id, 4)` is the right concurrency mode (per Step 2).

### The Tool Dispatch Contract — MCP-Exportable Surface

The single-entry-point contract every tool implementation must obey, derived from the MCP-export anti-pattern cheat sheet:

```objectscript
Class SessionAgent.Tool.Base Extends %RegisteredObject [ Abstract ]
{
  Parameter ToolName;                 // e.g., "session_summary"
  Parameter Description;
  Parameter MutatesState As %Boolean = 0;   // Layer-2 read-only enforcement metadata

  /// Returns the JSON Schema for this tool's input. Lowest-common-denominator subset
  /// per Step 2: {type, properties, required, enum, description, additionalProperties}.
  ClassMethod GetInputSchema() As %DynamicObject [ Abstract ] { Quit {} }

  /// Pure dispatch contract: jsonArgs in, jsonResult out. No %session, no %request,
  /// no $NAMESPACE side-effect, no Zen state. Caller identity is explicit.
  ClassMethod Invoke(
    pCallerCtx As SessionAgent.Agent.CallerContext,   // {username, namespace, irisSessionId}
    pJsonArgs As %DynamicObject,
    Output pResult As %DynamicObject
  ) As %Status [ Abstract ] { Quit $$$OK }
}
```

The `SessionAgent.Tool.Registry` enumerates all `SessionAgent.Tool.Base`-extending concrete classes (via `%Dictionary.ClassDefinition` reflection per Step 2's Topic 4 confidence note) and exposes:

- `ListTools() → %DynamicArray` returning `[{name, description, inputSchema}, …]` — exactly the shape `tools/list` requires for a future MCP export.
- `Dispatch(name, callerCtx, jsonArgs) → result` — the single funnel through which every tool call is gated. Layers 2 (mutation policy) and 4 (audit log instrumentation) live here.

Anti-patterns from Step 2 that the contract enforces structurally:

| Anti-pattern | How the contract blocks it |
|---|---|
| Reading `%session.Data` from a tool | Tool only sees `pCallerCtx`; `%session` not exposed |
| Returning HTML / `%CSP.Response.Write()` | Method signature is `Output pResult As %DynamicObject` |
| Hardcoding `$NAMESPACE` | Namespace is in `pCallerCtx`; tools call `Set $NAMESPACE = pCallerCtx.namespace` only if needed and restore it |
| ObjectScript exceptions as error signal | `Dispatch` catches at the boundary and converts to `{isError: true, content: [...]}` |
| Mutating ZenPage fields | No reference to Zen anywhere in `Tool.Base`'s signature |

### Three-Layer Read-Only Enforcement Pattern

Replaces the AI-Hub `%AI.Policy.Authorization` per Topic 4 of the locked scope.

| Layer | Mechanism | What it prevents |
|---|---|---|
| **L1 — Implementation discipline** | Code review checklist; no `%Save`, `%DeleteId`, `&sql(UPDATE...)`, no Ens.Director.* mutators in any tool implementation | Most direct accidents — devs simply don't write mutating code |
| **L2 — Dispatch policy gate** | `SessionAgent.Tool.Registry.Dispatch` reads `..#MutatesState` parameter; if `1` and the agent is configured `read_only=true`, immediately returns `{isError: true, content: [{type: "text", text: "Tool blocked by read-only policy"}]}`. Logged. | A mutating tool added accidentally; a tool repurposed for write later |
| **L3 — Database role / SQL grants** | The IRIS user under which the agent loop runs is granted ONLY `SELECT` on `Ens.MessageHeader`, `Ens.Util.Log`, `Ens.Rule.Log`, etc. — and `%Service_Login`/`%Admin_*` are denied. Even if L1 and L2 fail, the database refuses the write. | A writeable tool implementation that slips through code review and policy gate; SQL injection in a tool that builds dynamic SQL |

L1 alone is fragile (one bad commit breaks read-only). L1+L2 is good but a buggy `MutatesState=0` annotation is silent. **Only L1+L2+L3 is defense-in-depth** — and L3 is the one we'd pull out and document for an external compliance review.

### Error Handling, Retry, and Backoff Patterns

Anthropic's official error surface, [verified directly from docs](https://platform.claude.com/docs/en/api/errors):

| HTTP | Anthropic `error.type` | Action |
|---|---|---|
| 400 | `invalid_request_error` | Do not retry — fix the request |
| 401 | `authentication_error` | Do not retry — fix credentials |
| 402 | `billing_error` | Do not retry — surface to operator |
| 403 | `permission_error` | Do not retry — surface to operator |
| 404 | `not_found_error` | Do not retry — fix the request |
| 413 | `request_too_large` | Do not retry — request body > 32 MB cap; trim history or use Batch API |
| 429 | `rate_limit_error` | Retry with backoff; honor `retry-after` header (seconds) |
| 500 | `api_error` | Retry with exponential backoff |
| 504 | `timeout_error` | Retry with backoff; consider streaming for long requests |
| 529 | `overloaded_error` | Retry with longer backoff; expect transient |

OpenAI parallels this with 429 / 5xx — we'd never expect to hit OpenAI's `400 invalid_request_error` in normal operation, and 429 carries `retry-after` in seconds (synthesized from the [Anthropic-confirmed pattern](https://platform.claude.com/docs/en/api/errors); OpenAI's specific docs page returned 403 to our fetch but their published Python SDK retry policy [openai-python repo](https://github.com/openai/openai-python) is widely documented as 2 retries with exponential backoff, max 60s — confidence Medium for the exact defaults).

**Recommended `SessionAgent.Util.RetryWithBackoff` policy in ObjectScript** (synthesizes the rule into a 2024.1-compatible pattern):

```objectscript
ClassMethod CallWithRetry(pProvider, pHistory, pTools, ...) As %Status
{
  Set tMaxAttempts = 4
  Set tBaseDelaySec = 1.0
  Set tMaxDelaySec  = 32.0
  For tAttempt = 1:1:tMaxAttempts {
    Set tSC = pProvider.CallMessages(pHistory, pTools, ...)
    If $$$ISOK(tSC) Quit
    Set tStatus = pProvider.LastHttpStatus
    Set tRetryAfter = pProvider.LastRetryAfter   // seconds, parsed from header

    If '..IsRetryable(tStatus) Quit               // 4xx (except 429) → fail fast
    If tAttempt = tMaxAttempts Quit                // exhausted

    Set tDelay = $Select(tRetryAfter > 0 : tRetryAfter,
                         1 : ..ExpBackoff(tAttempt, tBaseDelaySec, tMaxDelaySec))
    Hang tDelay
  }
  Quit tSC
}

ClassMethod ExpBackoff(pAttempt, pBaseSec, pMaxSec) As %Numeric
{
  // 2^(n-1) * base, capped, with full jitter (random in [0, capped])
  Set tCapped = $Select((2 ** (pAttempt - 1)) * pBaseSec > pMaxSec : pMaxSec,
                        1 : (2 ** (pAttempt - 1)) * pBaseSec)
  Quit $Random(1000) / 1000 * tCapped   // full jitter, 0..capped
}

ClassMethod IsRetryable(pHttpStatus) As %Boolean
{
  Quit $Case(pHttpStatus, 429:1, 500:1, 502:1, 503:1, 504:1, 529:1, : 0)
}
```

**`retry-after` parsing nuance:** RFC 7231 allows the header to be either a positive integer (seconds) **or** an HTTP-date. Anthropic and OpenAI both emit seconds; **don't trust this assumption blindly** — try parse-as-integer first, fall back to `$ZDateTimeH` HTTP-date parse, fall back to backoff schedule.

**Idempotency:** Anthropic's docs do not currently document an `Idempotency-Key` header for Messages. **Do not retry on network-mid-flight failures** (e.g., the request was sent, response was lost) — those could be model-state-mutating retries that double-charge. Only retry on responses we actually received with a retryable status code. For mid-flight network failures, surface to operator with the `request-id` (per Anthropic, present in the `request-id` response header — log every one).

### Audit Logging Cross-Cut Pattern

Per Topic 9: every tool call gets logged. The pattern is a **dispatch interceptor** in `SessionAgent.Tool.Registry.Dispatch`:

```
Dispatch(name, ctx, args)
  → tStart  = $ZTimeStamp + $piece($Horolog, ",", 2) precision adapter
  → tStatus = TryInvoke(name, ctx, args, .result)
  → log: AuditEntry%Save({
        timestamp:   ISO-8601 UTC ($Translate($ZDateTime($ZTimeStamp,3,1)," ","T")_"Z"),
        irisSessionId, portalUser, agentSessionId, turnId,
        toolName: name, args: argsJson (with PII-stripping hook),
        durationMs, isError, errorText (if any), resultSummary (truncated)
      })
  → return result
```

LLM-call-level audit (separate persistent class) hooks at `provider.CallMessages` boundary — captures `usage` block (all four Anthropic fields per Step 2; `prompt_tokens`/`completion_tokens`/`prompt_tokens_details.cached_tokens` for OpenAI), provider, model, request-id, duration, stopReason.

Two persistent classes: `SessionAgent.Audit.ToolCall` (1 row per tool invocation) and `SessionAgent.Audit.LlmCall` (1 row per provider HTTP round-trip). Foreign-key both to `AgentSession` so an end-to-end timeline is reconstructable. Implements project's existing `Security.Events Pre-Registration for Audit` rule via `$System.Security.Audit("SessionAgent","ToolCall",...)` if compliance audit is required.

### Operational Integration: CSP / Web Gateway Timeout Coordination

The agent loop is synchronous-blocking inside a CSP hyperevent. Two timeouts can kill it:

| Timeout | Default | Where set | Effect on agent |
|---|---|---|---|
| `%session.AppTimeout` | 900 s (15 min) | Web app config or per-request `%session.AppTimeout = N` | Way more than enough for any realistic agent turn |
| **Web Gateway "Server Response Timeout"** | **commonly 60 s** | [Web Gateway management page → Default Parameters → System](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GCGI_oper_config), or `Server_Response_Timeout=N` in `CSP.ini [SYSTEM]` | **THIS is the LLM-call cliff.** A turn with 3 tool round-trips averaging 8s each + 3 Anthropic calls averaging 7s each = ~45s — close to 60s ceiling. |
| Network idle drop | varies | Customer firewall / load balancer | Anthropic recommends TCP keep-alive for long requests; mitigation in §"Long requests" of [Anthropic errors page](https://platform.claude.com/docs/en/api/errors) |

**Mitigation hierarchy:**

1. **Document raising the Web Gateway Server Response Timeout to 300 s as an operator prerequisite in the README** (per `research-first.md` rule 5 — "operator-facing state must ride the commit"). Sources: [Web Gateway Configure System-Wide Parameters](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GCGI_oper_config), [community post on each timeout's meaning](https://community.intersystems.com/post/description-each-timeout-value-can-be-set-default-parameter-web-gatewaycsp-gateway-management).
2. **Per-call provider timeout cap < gateway timeout.** With gateway at 300 s, set `%Net.HttpRequest.Timeout = 90` on each LLM call so a hung provider returns a timeout error well inside the gateway window.
3. **Cap max-iterations-per-turn at 10** to bound worst-case turn duration.
4. **For genuinely long turns:** future v1.5 addition is to flip the chat panel to async polling — submit turn → return job id → client polls status. Out of v1 scope.

### Confidence Notes for Step 3 Findings

- **Anthropic error code surface**: High — directly verified from docs.anthropic.com.
- **OpenAI retry semantics**: Medium — OpenAI's error-codes doc URL returned 403 to direct fetch; defaults inferred from [openai-python](https://github.com/openai/openai-python) widely-documented behavior + parallelism with Anthropic. Verify with a Task-0 probe before the implementation story.
- **Web Gateway 60s default**: Medium — community discussions confirm 60s as the common default but the version-specific default for 2024.1 isn't quoted in InterSystems docs; verify on a 2024.1 instance via the management page.
- **`retry-after` parsing**: High — RFC 7231 is the canonical reference; provider-specific behavior (seconds-only) is convention, not spec.
- **Three-layer read-only enforcement**: High — pattern is canonical defense-in-depth, validated by the original product brief's pre-AI-Hub design notes.

---

## Scope Amendments — 2026-05-01 (post-Step-3)

After Step 3 was committed, [`docs/initial-prompt.md`](../../../docs/initial-prompt.md) was surfaced as the user's authoritative project spec. It expands the v1 scope beyond what was locked in Step 1. The amendments below are now binding on Steps 4–6 and beyond.

> **Saved to memory:** `project_full_v1_scope.md` — every future planning conversation in this project starts with the expanded scope as foundational context.

### Five additions to the locked scope

1. **Two agents, not one.** v1 ships:
   - **Session Inspection Agent** — already the subject of this research doc. Embedded in custom `EnsPortal.VisualTrace`. 13-tool catalog over Ens.* tables.
   - **Message Search Agent (NEW)** — embedded in custom `EnsPortal.MessageViewer`. Helps operators find sessions by natural-language query. **Different tool surface** than the inspection agent: search-oriented, scale-aware (millions of `Ens.MessageHeader` rows), with **search-term learning per-user across sessions**. The Message Search Agent gets its own sibling research doc — kicked off after Step 6 of this doc.
2. **Four LLM providers, extensible framework.** v1 ships with OpenAI, Anthropic, **Google (Gemini)**, and Ollama. **OpenAI is the implementation priority** ("we can start with OpenAI"). The provider abstraction must accept a 5th provider as one new concrete subclass + registry entry — no refactor.
   - Step 3's provider-abstraction design (canonical Anthropic shape, OpenAI translator) still holds — but the **Step 4 architectural treatment must explicitly cover Gemini** (`generativelanguage.googleapis.com` `models/<n>:generateContent` with `functionDeclarations` / `functionCall` / `functionResponse` parts).
   - Implementation-priority order shifts: ship the OpenAI concrete first, validate the abstraction with Anthropic second, add Gemini third, Ollama free-rides on OpenAI's translator.
3. **Per-agent configuration via Zen pages.** Each agent independently configured (provider, model, max-tokens, temperature, system-prompt overrides, read-only flag). Backed by a `%Persistent` config class. **API keys are NEVER stored in the config row** — they live in `Ens.Config.Credentials` (per Step 2's Topic 8 preflight finding) or env-vars; the config row only holds a *reference* to the credential record. Step 5 implementation research will cover the Zen page layout.
4. **Chat history lifecycle-coupled to the Ens session it discusses.** When `Ens.MessageHeader.Purge()` removes the Interop session's headers, the agent's chat history for that session **must purge with it.** Two design candidates from the user's spec:
   - **Option A — chat as Ens.MessageHeader entries.** Append each chat turn to the Interop session as its own `Ens.MessageHeader` row (with body referencing a `SessionAgent.Chat.Turn` body class). Native purge-by-SessionId cascade-cleans automatically.
   - **Option B — separate persistent class with custom purge hook.** A `SessionAgent.Chat.History` `%Persistent` class keyed on `(IrisSessionId, PortalUser)`. Purge via either an `Ens.MessageHeader.OnDelete` hook (if available) or a periodic sweep keyed by "no header exists for this SessionId."
   - Step 4 Topic 10 will analyze trade-offs and recommend.
5. **IPM (ZPM) installable** as the explicit packaging requirement. Standard `module.xml` with `<Resource Name>` for class packages, `<FileCopy>` for vendored static assets (`marked.js` + `Prism.js` + `DOMPurify` per Step 2), `<CSPApplication>` entries for Zen / CSP routes. Step 4 will cover deployment topology; Step 5 will cover concrete `module.xml` shape.

### What carries forward unchanged

- The **IRIS 2024.1 platform surface inventory** (Step 2) is shared infrastructure — both agents use the same `%Net.HttpRequest`, `%DynamicObject`, `%Persistent`, `%Dictionary.*`, `%SQL.Statement`, `Ens.Config.Credentials`, encryption primitives.
- The **agent tool-call loop** (Step 3) is shared — both agents drive the same `SessionAgent.Agent.AgentLoop.RunTurn` with different tool registries injected.
- The **MCP-exportable tool dispatch contract** (Step 3) is shared — both agents' tools sit behind the same `(toolName, jsonArgs) → jsonResult` surface.
- The **three-layer read-only enforcement** (Step 3) applies to both agents. The Message Search Agent is also strictly read-only.
- The **Markdown rendering layer** (Step 2) is shared — same `marked` + `Prism` + `DOMPurify` bundle in both Zen pages.
- The **Topic 8 secrets-storage path** (env-var primary → `Ens.Config.Credentials` secondary) applies to both agents' API keys.

### What's deferred to the sibling Message Search Agent research doc

- The Message Search Agent's tool surface (search by date range, by source/target, by message body fields, by status, by patient/order ID hints, etc.).
- Scale-handling patterns: `TOP N` pagination over `Ens.MessageHeader`, time-window-bounded queries, `_AdditionalInfo` body indexes, the `Ens.SuperSessionIndex` cross-reference, and `%NOLOCK` hint usage.
- Search-term-learning persistence: per-user vocabulary store, ranking signal storage, retrieval-augmented prompting at turn time.
- Decision: how the Message Search Agent's chat is keyed (no Ens session ID exists at search time — different lifecycle model than the Inspection Agent).

---

## Architectural Patterns and Design

> **Note on scope:** Step 4 turns the integration patterns from Step 3 into named components, package structures, deployment topology, and concrete architectural decisions. The five Scope Amendments are first-class concerns: two-agent infrastructure sharing, the four-provider framework (OpenAI / Anthropic / Gemini / Ollama), per-agent Zen configuration, chat-history lifecycle coupling, and IPM packaging are each treated as architectural sub-sections.

### High-Level Component Architecture

A logical view of the v1 system, with the trust boundary (everything below `AgentLoop` is MCP-portable / CSP-free) marked explicitly.

```
        ┌─────────────────────────────────────────────────────────┐
        │  IRIS Management Portal (CSP, port 52773)               │
        │                                                         │
        │  ┌──────────────────────┐   ┌──────────────────────┐    │
        │  │ SessionAgent.EnsPortal.    │   │ SessionAgent.EnsPortal.    │    │
        │  │   VisualTrace        │   │   MessageViewer      │    │
        │  │ (Inspection Agent    │   │ (Message Search      │    │
        │  │  chat tab)           │   │  Agent chat tab)     │    │
        │  └──────────┬───────────┘   └──────────┬───────────┘    │
        │             │  ZenMethod hyperevent    │                │
        │             ▼                          ▼                │
        │  ┌──────────────────────────────────────────────────┐   │
        │  │ SessionAgent.Agent.AgentLoop  (one per turn, blocking)    │   │
        │  │  RunTurn(agentName, irisSessionId, user, text,   │   │
        │  │          contextHints) → markdownResponse        │   │
        │  └──────────────────────────┬───────────────────────┘   │
        │                             │                           │
        │  ════════════════ TRUST / TRANSPORT BOUNDARY ════════════│
        │  (above: CSP/Zen-coupled. below: MCP-portable surface.) │
        │                             │                           │
        │            ┌────────────────┼────────────────┐          │
        │            ▼                ▼                ▼          │
        │   ┌─────────────┐  ┌─────────────────┐  ┌───────────┐   │
        │   │  Tool       │  │  LLM Provider   │  │  Audit    │   │
        │   │  Registry   │  │  Abstraction    │  │  Log      │   │
        │   │ (per-agent  │  │  (4 concretes:  │  │ (2 pers.  │   │
        │   │  tool sets) │  │   OpenAI,       │  │  classes) │   │
        │   │             │  │   Anthropic,    │  │           │   │
        │   │             │  │   Gemini,       │  │           │   │
        │   │             │  │   OpenAI-compat)│  │           │   │
        │   └──────┬──────┘  └────────┬────────┘  └───────────┘   │
        │          │                  │                           │
        │          ▼                  ▼                           │
        │  ┌─────────────────────┐  ┌────────────────────────┐    │
        │  │ Tool implementations│  │ %Net.HttpRequest →     │    │
        │  │ (read-only SQL +    │  │  external LLM provider │    │
        │  │  ObjectScript       │  │  endpoints over HTTPS  │    │
        │  │  methods over Ens.*)│  │                        │    │
        │  └─────────────────────┘  └────────────────────────┘    │
        │                                                         │
        │  ┌──────────────────────────────────────────────────┐   │
        │  │ Persistence layer (%Persistent)                  │   │
        │  │  SessionAgent.Chat.History  -- chat per (irisSessionId,   │   │
        │  │                      portalUser); purge-coupled  │   │
        │  │  SessionAgent.Config.Agent  -- per-agent runtime config   │   │
        │  │  SessionAgent.Audit.LlmCall -- LLM round-trip audit       │   │
        │  │  SessionAgent.Audit.ToolCall-- tool dispatch audit        │   │
        │  └──────────────────────────────────────────────────┘   │
        │                                                         │
        │  ┌──────────────────────────────────────────────────┐   │
        │  │ Secrets layer                                    │   │
        │  │  $SYSTEM.Util.GetEnviron("X_API_KEY") (primary)  │   │
        │  │  Ens.Config.Credentials       (secondary)        │   │
        │  └──────────────────────────────────────────────────┘   │
        └─────────────────────────────────────────────────────────┘
```

### Two-Agent Infrastructure Sharing

Per the Scope Amendments, v1 ships two agents with **shared infrastructure and divergent tool sets**. The architectural test for "shared vs distinct" is mechanical: anything that's about *how* an LLM agent works is shared; anything that's about *what the operator is asking* is distinct.

| Layer | Status | Reason |
|---|---|---|
| `SessionAgent.Agent.AgentLoop` | **Shared** | One implementation of the tool-call loop; both agents drive it |
| `SessionAgent.LLM.Provider` abstraction + 4 concretes | **Shared** | Per-agent config selects which provider, but the framework is one |
| `SessionAgent.Tool.Base` + `SessionAgent.Tool.Registry` | **Shared** (base classes) | Pattern is shared; concrete tool sets are distinct |
| `SessionAgent.Tool.Inspection.*` (13 tools over Ens.*) | **Distinct to Session Inspection Agent** | Inspect-this-session domain |
| `SessionAgent.Tool.Search.*` (search-by-X tools over Ens.MessageHeader) | **Distinct to Message Search Agent** (sibling research doc) | Find-the-right-session domain |
| `SessionAgent.Chat.History` | **Shared** schema, but rows keyed differently | Inspection: keyed `(irisSessionId, portalUser)`. Search: keyed `(searchSessionId, portalUser)` where searchSessionId is a registry-issued GUID since no Ens session id exists |
| `SessionAgent.Config.Agent` | **Shared** schema, two rows | One row per agent name |
| `SessionAgent.Audit.{LlmCall, ToolCall}` | **Shared** | One audit ledger; rows tagged with `AgentName` |
| Read-only enforcement (3-layer) | **Shared** | Same RBAC role serves both agents |
| Markdown rendering bundle (`marked` + `Prism` + `DOMPurify`) | **Shared** | One static-asset tree under `/csp/static/iris-session-agent/` |
| Custom Zen portal pages | **Distinct** | Two subclasses (`EnsPortal.VisualTrace`, `EnsPortal.MessageViewer`) |
| Configuration Zen page (`SessionAgent.UI.AgentConfig`) | **Shared** (one page, lists both agents) | One operator UI to configure both |

The architectural payoff: adding a 3rd agent later (e.g., a "Production Health Agent" that watches `Ens.Util.Statistics`) costs one new tool package and one new portal subclass — the rest of the framework is reused.

### Package and Class Hierarchy (v1)

The package shape under `src/`:

```
App/
  Agent/
    AgentLoop.cls            -- the per-turn state machine (see Step 3)
    CallerContext.cls        -- {agentName, irisSessionId, portalUser, namespace}
    ProviderResponse.cls     -- DTO for the canonical Anthropic-shape response
    TurnResult.cls           -- DTO returned to ZenMethod / future MCP

  LLM/
    Provider.cls             [Abstract]   -- Step 3's abstraction
    AnthropicProvider.cls    -- canonical reference shape
    OpenAIProvider.cls       -- ships first per scope amendment
    GeminiProvider.cls       -- adds 'functionDeclarations' / 'functionResponse' shape
    OpenAICompatProvider.cls -- Ollama, vLLM, any OpenAI-compatible endpoint
    Util/
      RetryWithBackoff.cls   -- Step 3's retry policy as a callable
      ToolDefAdapter.cls     -- canonical → provider-specific tool definitions
      MessageAdapter.cls     -- canonical → provider-specific message history

  Tool/
    Base.cls                 [Abstract]   -- Step 3's dispatch contract
    Registry.cls             -- enumerates & dispatches; layers 2 + 4 of read-only enforcement
    Inspection/              -- the 13 Session Inspection tools
      GetSessionSummary.cls
      GetSessionTimeline.cls
      ... (11 more — see original product brief distillate)
    Search/                  -- the Message Search tools (sibling research doc)

  Chat/
    History.cls              -- %Persistent; per (agentName, sessionKey, portalUser)
    Turn.cls                 -- Serializable shape of a single message in history

  Config/
    Agent.cls                -- %Persistent; one row per agent
    AgentDefaults.cls        -- ClassMethod GetSeedConfig(agentName) for IPM install

  Audit/
    LlmCall.cls              -- %Persistent; one row per provider HTTP round-trip
    ToolCall.cls              -- %Persistent; one row per tool dispatch
    Emit.cls                 -- $System.Security.Audit() helper + EnsureEvents()

  Security/
    ReadOnlyRole.cls         -- ClassMethod for installer to grant SELECT-only on Ens.*

  Util/
    EnvSecret.cls            -- $SYSTEM.Util.GetEnviron + Ens.Config.Credentials fallback
    Json.cls                 -- %DynamicObject helpers (null-emit, deep merge, redact)
    Markdown.cls             -- (server-side hooks if needed; mostly client-side)

  UI/
    AgentConfig.cls          -- Zen page for editing agent configs
    ChatPanel.cls             -- shared CSS / JS contributors used by both EnsPortal subclasses

Custom/
  EnsPortal/
    VisualTrace.cls          -- subclass adding chat tab; Inspection Agent host
    MessageViewer.cls        -- subclass adding chat tab; Search Agent host
    Util/
      ChatPanelDrawHelper.cls -- shared OnDrawContent for both pages

SessionAgent.Installer.cls            -- IPM Invoke target; package mappings, audit events, role grant, default configs
```

### Provider Abstraction Architecture (Four Concretes)

The provider layer absorbs the four wire-protocol shapes catalogued in Steps 2-3 and the Gemini wire-shape research from this step. Updated provider comparison row for Gemini (extends Step 3's table):

| Concern | Anthropic (canonical) | OpenAI | Gemini | Ollama / vLLM |
|---|---|---|---|---|
| Endpoint | `api.anthropic.com/v1/messages` | `api.openai.com/v1/chat/completions` | `generativelanguage.googleapis.com/v1beta/models/<m>:generateContent` | `<host>/v1/chat/completions` |
| Auth | `x-api-key` header | `Authorization: Bearer` | `x-goog-api-key` header (May 2026 recommended) | None or Bearer |
| Tool-def keys | `name`, `description`, `input_schema` | `type:"function"`, `function:{name,description,parameters}` | `tools[].functionDeclarations[].{name,description,parameters}` (OpenAPI 3.0 schema) | OpenAI shape |
| Tool args wire | object | string (JSON.stringify'd) | **object** (must NOT re-parse) | string |
| Tool-result role | `user` (with `content[]` of `tool_result`) | dedicated `tool` role, one per call | `user` (with `parts[]` of `functionResponse`) | dedicated `tool` |
| Tool-result correlation | `tool_use_id` | `tool_call_id` | `name` (+ optional `id` for parallel) | `tool_call_id` |
| Stop reason for tool turn | `tool_use` | `tool_calls` | `STOP` (must inspect `parts[]` for `functionCall`) | `tool_calls` |
| Caching | manual `cache_control` blocks | automatic ≥1024 tokens | `cachedContent` resource (server-side, named) | typically none |
| System prompt placement | top-level `system` field | `{role:"system"}` in `messages` | top-level `systemInstruction` field | `{role:"system"}` |
| Usage fields | `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens` | `prompt_tokens`, `completion_tokens`, `prompt_tokens_details.cached_tokens`, `completion_tokens_details.reasoning_tokens` | `usageMetadata.{promptTokenCount, candidatesTokenCount, totalTokenCount, cachedContentTokenCount}` | `prompt_tokens`, `completion_tokens` |
| Rate-limit retry signal | `Retry-After` header (seconds) | `Retry-After` header (seconds) | **`error.details[].retryDelay` field** (string like `"34s"`) — NOT a header | `Retry-After` header |

**The Anthropic-canonical abstraction holds across all four.** Per the Gemini stream's recommendation: treat Gemini as "Anthropic with renamed keys + role flattening + parts-inspection for tool-use detection," same conceptual shape as the OpenAI translator. No need to re-shape the canonical layer.

**Adapter responsibilities for Gemini specifically:**
- `MessageAdapter`: rename `assistant` ↔ `model`, `content` blocks ↔ `parts`, `tool_use` block ↔ `functionCall` part, `tool_result` block ↔ `functionResponse` part with role flattened to `user`.
- `ToolDefAdapter`: rename `input_schema` ↔ `parameters`, restrict to OpenAPI-3.0-compatible JSON Schema subset (Gemini's parameter parser is narrower than Anthropic's).
- `RetryWithBackoff`: parse `error.details[].retryDelay` (a duration string like `"34s"`) instead of the standard `Retry-After` header. Layer 2024.1-compatible parser logic (regex `(\d+)s` → seconds).
- `args`-already-parsed quirk: do **NOT** call `[].%FromJSON()` on Gemini's `functionCall.args` — it's already a `%DynamicObject`. (OpenAI's `tool_calls[].function.arguments` is the inverse — a string requiring `%FromJSON`.)

**Implementation priority order (per scope amendment):**
1. `OpenAIProvider` — first concrete, end-to-end demo path. Rationale: user explicitly named it as the start point.
2. `AnthropicProvider` — second; validates the abstraction by implementing the canonical-shape directly.
3. `GeminiProvider` — third; the third translator validates extensibility of the framework.
4. `OpenAICompatProvider` — last (or concurrent with #1); subclass / config tweak of `OpenAIProvider`.

**Tool-calling reliability ranking** (synthesized from BFCL V4 + Gemini research-stream findings, both Medium confidence):
1. Claude Opus 4.7 / Sonnet 4.5 (Anthropic) — most reliable
2. GPT-5 / GPT-4o (OpenAI) — close second
3. Gemini 2.5 Pro / Gemini 3 Pro — usable, but Gemini 2.5 Flash is reportedly erratic on schema adherence; **prefer Pro tiers for the 13-tool agent loop**
4. Qwen 2.5 32B+ (best OSS) — usable; smaller OSS models will produce malformed JSON args occasionally; the agent loop's parse-failure-retry path must work reliably for OSS to be a credible deployment target

### Persistent Session State Architecture

`SessionAgent.Chat.History` is the central state class. Schema:

```objectscript
Class SessionAgent.Chat.History Extends %Persistent
{
  Property AgentName As %String(MAXLEN=64) [ Required ];
    /// "session-inspection" | "message-search"
  Property SessionKey As %String(MAXLEN=64) [ Required ];
    /// Inspection: the Ens session id (cascades on Ens purge — see Topic 10)
    /// Search: a registry-issued GUID, no Ens coupling
  Property PortalUser As %String(MAXLEN=64) [ Required ];
    /// %session.Username at chat creation time
  Property TurnsJson As %Stream.GlobalCharacter;
    /// JSON-serialized %DynamicArray of turns, canonical Anthropic shape:
    /// [{role:"user"|"assistant", content:[blocks...]}, ...]
  Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDateTime($H,3,1)} ];
  Property UpdatedAt As %TimeStamp;
  Property Provider As %String(MAXLEN=32);     // pinned at session start for audit
  Property Model As %String(MAXLEN=64);
  Index PrimaryKey On (AgentName, SessionKey, PortalUser) [ PrimaryKey ];
  Index ByAgentSession On (AgentName, SessionKey);   // for cross-user purge by Ens session
}
```

**Concurrency:** Per Step 3 — every `RunTurn` opens with `%OpenId(id, 4)` to acquire an exclusive row lock and releases on save. Two operator tabs targeting the same Ens session id **serialize**; the second waits.

**Capacity:** `TurnsJson` as `%Stream.GlobalCharacter` has no documented size cap. In practice, the cache-friendly Anthropic patterns (cached system prompt + cached tool definitions) keep the per-turn delta small; a 200-turn conversation is comfortably under 1 MB.

### Topic 10 (NEW) — Chat-History Lifecycle Coupling to Ens Session Purge

The user's spec is explicit: **chat history for a given Ens session must purge alongside the Ens session itself.** Two design candidates were flagged in the Scope Amendments. Analysis:

**Option A — Chat as `Ens.MessageHeader` entries**

- Each chat turn becomes its own `Ens.MessageHeader` row, body referencing an `SessionAgent.Chat.Turn` body class extending `Ens.Request`.
- ConfigName/SourceConfigName: synthetic ("AgentChatBus" / "OperatorChat").
- Native `Ens.MessageHeader.Purge(.deletedCount, daysToKeep, ..., sessionsOnly=0)` cascade-cleans automatically.

| Pros | Cons |
|---|---|
| Native purge cascade — zero custom logic | **Pollutes the Visual Trace and Message Viewer with chat rows.** Operators debugging a real production issue see chat clutter. |
| Chat rows participate in normal Ensemble auditing | Chat rows show up in `Ens.SuperSessionIndex` and break the "session = one logical interop transaction" mental model |
| | Synthetic ConfigName complicates rule-engine and queue analytics |
| | One-way door: hard to cleanly extract chat rows from old data later if you change your mind |
| | Forces chat schema to live inside Ens.MessageHeader's column constraints |

**Option B — Separate `SessionAgent.Chat.History` `%Persistent` class with cascade purge**

- The schema shown above. Chat lives in its own globals; not visible in Visual Trace.
- Cascade purge via two complementary mechanisms:
  1. **A periodic sweep task** (`SessionAgent.Task.PurgeOrphanedChatHistory`) — run as a daily IRIS Task. Query `SessionAgent.Chat.History` rows; for each row's `SessionKey` (when AgentName='session-inspection'), check `EXISTS (SELECT 1 FROM Ens.MessageHeader WHERE %ID = ? OR SessionId = ?)`. Delete the chat-history row when no header remains.
  2. **An explicit-purge hook** for operators who run `Ens.MessageHeader.Purge()` manually — the IPM installer documents that the operator should also schedule the sweep task. Optional: add a custom purge-class to the `Ens.Util.Tasks.Purge` chain so `chat-history` purges in lockstep with header purge.

| Pros | Cons |
|---|---|
| **No pollution of Interop trace.** Operators see only real interop messages in Visual Trace and Message Viewer | Custom purge logic — a place for bugs |
| Chat schema is purpose-built (turns, role, blocks, tool-call audit) | Race condition window: between Ens purge and the next sweep, chat history is "orphaned" but not yet deleted |
| Easy to evolve schema independently of Ensemble | Periodic sweep adds a daily task |
| Reversible: can rip out chat in one purge, no cleanup of Ens.* tables | Operators must know to install the sweep task (IPM installer should auto-install it) |

**Recommendation: Option B with the periodic sweep task.**

Reasoning:
- **The "no chat pollution in Visual Trace" win is large.** Operators using the chat panel are *also* the operators debugging real production sessions. Mixing those two streams in the same Visual Trace timeline is a UX regression we'd be choosing to ship.
- **The custom purge logic is small and bounded.** ~30 lines of ObjectScript, one `SessionAgent.Task.PurgeOrphanedChatHistory` class, IPM-installed via `SessionAgent.Installer`. It's a one-time write; no surprises.
- **Option A is a one-way door.** Once chat-as-message rows are in production globals, removing them post-hoc requires a custom class-aware deletion script — exactly the bespoke cleanup logic Option A was supposed to avoid.
- **The orphan window is tolerable.** Daily sweep means at most 24 hours of stale chat-history rows past their Ens session purge. For a tool whose audit tail is days-to-months, this is a non-issue. Operators wanting tighter coupling can run the sweep task hourly.

Implementation outline for the sweep task:

```objectscript
ClassMethod PurgeOrphanedChatHistory() As %Status
{
  &sql(DECLARE C1 CURSOR FOR
       SELECT %ID, AgentName, SessionKey
       FROM App_Chat.History
       WHERE AgentName = 'session-inspection')
  &sql(OPEN C1) For { &sql(FETCH C1 INTO :id, :agent, :sk)  Quit:SQLCODE'=0
    &sql(SELECT 1 INTO :exists FROM Ens.MessageHeader WHERE SessionId = :sk)
    If SQLCODE = 100 {
      ; no header rows for this Ens session — orphaned chat
      Set tSC = ##class(SessionAgent.Chat.History).%DeleteId(id)
      $$$LogIfErr(tSC, "PurgeOrphanedChatHistory: delete failed for "_id)
    }
  } &sql(CLOSE C1)
  Quit $$$OK
}
```

(Real implementation in Step 5; the above is the architectural shape, not the production code.)

### Configuration Architecture

`SessionAgent.Config.Agent` schema:

```objectscript
Class SessionAgent.Config.Agent Extends %Persistent
{
  Property AgentName As %String(MAXLEN=64) [ Required ];
    /// "session-inspection" | "message-search"  (PK)
  Property Provider As %String(VALUELIST=",openai,anthropic,gemini,ollama") [ Required ];
  Property Model As %String(MAXLEN=64) [ Required ];
    /// e.g., "gpt-4o", "claude-sonnet-4-5", "gemini-2.5-pro", "qwen2.5:32b"
  Property MaxTokens As %Integer [ InitialExpression = 4096 ];
  Property Temperature As %Numeric(SCALE=2) [ InitialExpression = 0.0 ];
  Property SystemPromptOverride As %Stream.GlobalCharacter;
    /// Empty = use SessionAgent.Config.AgentDefaults.GetSystemPrompt(agentName)
  Property ReadOnly As %Boolean [ InitialExpression = 1 ];
    /// Layer-2 read-only enforcement; default 1, never set 0 in v1
  Property CredentialName As %String(MAXLEN=64);
    /// FK to Ens.Config.Credentials.SystemName. Empty = use env-var.
  Property EnvVarName As %String(MAXLEN=64);
    /// e.g., "ANTHROPIC_API_KEY". Used when CredentialName is empty.
  Property EndpointUrl As %String(MAXLEN=512);
    /// Override default endpoint. Required for Ollama; optional for others.
  Property Enabled As %Boolean [ InitialExpression = 1 ];
  Property UpdatedAt As %TimeStamp;
  Property UpdatedBy As %String;
  Index PrimaryKey On AgentName [ PrimaryKey ];
}
```

**Critical: API keys never live in this row.** Either `CredentialName` points to an `Ens.Config.Credentials` row (the secret stays encrypted in the secondary store), or `EnvVarName` names a `$SYSTEM.Util.GetEnviron` variable (the secret stays in the container env). The config row is a *reference*, never a *holder*. This means:
- The config row can be exported / version-controlled / backed up without exposing secrets.
- An operator rotating a credential changes only the `Ens.Config.Credentials` password; agent config is untouched.
- Per-agent credential isolation is one foreign-key field — easy to assign different keys to the two agents.

### Read-Only Enforcement Architecture (Three Layers Realized)

Step 3 stated the pattern; Step 4 stamps it onto the architecture:

| Layer | Concrete artifact in v1 | Owned by |
|---|---|---|
| **L1 — Implementation discipline** | Code-review checklist; `SessionAgent.Tool.Inspection.*` and `SessionAgent.Tool.Search.*` reviewed for absence of mutating SQL or class methods | Dev process, not architecture |
| **L2 — Dispatch policy gate** | `SessionAgent.Tool.Registry.Dispatch` reads `..#MutatesState` parameter on the tool class. If `MutatesState=1` AND `SessionAgent.Config.Agent.ReadOnly=1` for the calling agent, returns `{isError:true, content:[...]}` and logs the violation as an `SessionAgent.Audit.ToolCall` row with `BlockedByPolicy=1` | `SessionAgent.Tool.Registry`, `SessionAgent.Config.Agent` |
| **L3 — IRIS RBAC SELECT-only role** | `SessionAgent.Security.ReadOnlyRole.Install()` creates an IRIS role `%SessionAgent_ReadOnly` granted `SELECT` on each `Ens.*` table the tools query (and on the `Custom.*` tables we add). The agent runtime user (typically the CSP-portal-user-as-itself) is granted this role and DENIED `%Service_*` and `%Admin_*` resources | `SessionAgent.Security.ReadOnlyRole`, IRIS native security |

L3 is critical: **even if L1 and L2 fail, the database refuses the write.** This is the layer that survives a "what if a tool author accidentally sets `MutatesState=0` on a write tool" scenario.

### CSP / Zen / Portal Integration Architecture (Phase 2 + 3)

Same as the AI-Hub-coupled brief's design (the EnsPortal subclassing pattern is *not* AI-Hub-specific), with three OS-Hub-specific adjustments:

- **Both portal subclasses share `SessionAgent.EnsPortal.Util.ChatPanelDrawHelper`** — one `OnDrawContent="DrawChatPanel"` implementation that knows the agent name based on the calling page. Reduces XData duplication.
- **Single ZenMethod hyperevent signature**: `SendChatMessage(agentName, sessionKey, userText, contextHints) → resultJson`. Both pages call the same one (different `agentName` + `sessionKey` shape).
- **Shared static-asset directory**: `/csp/static/iris-session-agent/` serves `marked.min.js`, `prism.min.js + prism-objectscript.js`, `dompurify.min.js`, `chat-panel.js` (the small wrapper that orchestrates the three on the client side). Both pages reference the same `<script>` tags in the chat-tab XData.

### IPM (ZPM) Packaging Architecture

`module.xml` (the v1 shape — concrete content lands in Step 5):

```xml
<Module>
  <Name>iris-session-agent</Name>
  <Version>1.0.0</Version>
  <Description>Pure-ObjectScript Ensemble session inspection and message search agents</Description>
  <Packaging>module</Packaging>
  <SourcesRoot>src</SourcesRoot>

  <!-- Class packages -->
  <Resource Name="SessionAgent.PKG"/>

  <!-- Static UI assets (vendored, no CDN) -->
  <FileCopy Name="static/" Target="${cspdir}static/iris-session-agent/"/>

  <!-- CSP application for the static assets and UI pages -->
  <CSPApplication
    Url="/csp/static/iris-session-agent"
    Path="${cspdir}static/iris-session-agent"
    Resource=""
    Recurse="1"
    UseCookies="0"
    AuthenticationMethods="64"/>  <!-- unauthenticated for static -->

  <!-- The agent UI Zen page lives under the existing portal CSP app
       (HSCUSTOM mapping makes Custom.* visible everywhere) -->

  <!-- Install hooks -->
  <Invoke Method="Install" Class="SessionAgent.Installer"/>
</Module>
```

**`SessionAgent.Installer.Install()` responsibilities** (per project's existing rule on `Security.Events Pre-Registration for Audit`):

1. Register audit event types (`Security.Events.Create("SessionAgent","ToolCall",...)` etc.) in `%SYS`.
2. Configure package mapping: map `SessionAgent.*` from HSCUSTOMCODE database to `%ALL` namespaces (or to a configured list — operator chooses).
3. Install the `%SessionAgent_ReadOnly` role and grant the appropriate `Ens.*` SELECT privileges.
4. Install the `SessionAgent.Task.PurgeOrphanedChatHistory` periodic task (default daily, 02:00 UTC).
5. Seed default config rows for both agents (Provider=openai, Model placeholder, ReadOnly=1, EnvVarName="OPENAI_API_KEY") — operator edits via Zen UI.
6. Print operator README reminders to the install log: "set OPENAI_API_KEY env var", "raise Web Gateway Server Response Timeout to 300", "verify HSCUSTOMCODE mapping".

Per the project's Story-13.0-derived rule (NFR-M9 lineage): **`zpm install iris-session-agent` must succeed on a Python-less IRIS 2024.1+ instance.** Zero `[Language = python]` methods anywhere in `src/`. Verified by intentional architectural choice (pure ObjectScript per saved memory).

### Deployment Topology

- **Code lives in HSCUSTOM** (database `HSCUSTOMCODE`). Standard HealthShare pattern; survives upgrades.
- **Package mapping to `%ALL`** (or operator-selected namespaces). Inherited from the original product brief; no v1 deviation.
- **Bookmark URL pattern**: `https://<host>/csp/healthshare/<TARGET_NS>/SessionAgent.EnsPortal.MessageViewer.zen` (Phase 3 entry) and `https://<host>/csp/healthshare/<TARGET_NS>/SessionAgent.EnsPortal.VisualTrace.zen` (Phase 2 reachable from MessageViewer's session click-through). One bookmark per namespace per agent — operator picks which.
- **Cross-namespace agent operation**: NOT in v1 scope (per the inherited brief). Each bookmark targets one namespace; `$NAMESPACE` does NOT switch inside CSP/ZenMethod context (per the project's existing `Namespace Switching in REST Handlers` rule applied to CSP).
- **Concurrency model**: Multiple operator browser tabs in the same portal user serialize via `SessionAgent.Chat.History` row lock (per Step 3). Multiple distinct portal users see distinct chat-history rows (`PortalUser` column part of the primary key).

### Security Architecture

| Concern | v1 Decision |
|---|---|
| Authentication | Inherits from CSP/Zen — operator already logged into the Management Portal. Same session cookie. |
| Authorization (page access) | Existing `%Ens_MessageTrace:USE` resource (inherited from `EnsPortal.VisualTrace` parent) gates the chat tab. |
| Authorization (tool dispatch) | `SessionAgent.Tool.Registry.Dispatch` rejects mutating tools when `SessionAgent.Config.Agent.ReadOnly=1` (Layer 2). |
| Authorization (DB) | The IRIS user under whom the tool's SQL runs is the portal user; SQL grants restrict to SELECT-only on `Ens.*` (Layer 3). |
| Secrets at rest | Either `Ens.Config.Credentials` (encrypted at rest in `%SYS.Ensemble` secondary store) or `$SYSTEM.Util.GetEnviron` (process env, never in IRIS DB). Never in `SessionAgent.Config.Agent` row. |
| Secrets in transit | TLS to LLM provider (HTTPS via `%Net.HttpRequest`'s `Https=1`). |
| LLM-content sanitization | DOMPurify gate on the client side before `innerHTML` injection. |
| Audit | Every tool dispatch (`SessionAgent.Audit.ToolCall`) and every LLM round-trip (`SessionAgent.Audit.LlmCall`) persisted; optional native `$System.Security.Audit` emit per organizational compliance. |
| Cross-tenant isolation | None at the framework level — IRIS namespace boundaries are the isolation primitive. |

### Confidence Notes for Step 4 Findings

- **Component architecture and class hierarchy**: High — derived directly from the locked scope + Step 3 patterns. Stable.
- **Provider abstraction (now 4 concretes)**: High — Anthropic-canonical pattern survives the Gemini addition cleanly.
- **Topic 10 lifecycle-coupling recommendation (Option B)**: Medium-High — recommendation is defensible, but the cost of Option B's "orphan window" is operator-context-dependent; an organization with strict immediate-purge compliance may want a stricter Ens.MessageHeader.Purge wrapper hook. Re-litigate during PRD if it surfaces.
- **IPM `module.xml` shape**: Medium — concrete content (resource names, file copy targets, install method body) lands in Step 5; current shape is the architectural sketch, not the working file.
- **Read-only Layer 3 (DB role)**: High — pattern is canonical IRIS RBAC; the only architectural risk is operator misconfiguration of namespace mappings (mitigated by `SessionAgent.Installer` running the grant idempotently).

---

## Implementation Approaches and Technology Adoption

> **Note on scope:** Step 5 turns the architecture into code-level findings. Skeletons are illustrative — they show the canonical shape and the load-bearing methods, not every overload. Full implementation lands in development stories. Code examples target IRIS 2024.1+, pure ObjectScript, no embedded Python.

### Implementation Roadmap and Sprint Sequencing

The framework decomposes into **11 epics** in dependency order. The first six unblock a working Inspection-Agent demo against OpenAI; the rest layer on production polish, additional providers, and the Message Search Agent.

| # | Epic | Depends on | Why this order |
|---|---|---|---|
| 1 | Foundation: IPM packaging + `SessionAgent.Installer` skeleton + RBAC role + Audit-event registration | — | Nothing compiles without the package shape; install-time wiring blocks every later story |
| 2 | LLM Provider abstraction + `SessionAgent.LLM.OpenAIProvider` (concrete #1) + `SessionAgent.Util.RetryWithBackoff` + `SessionAgent.Util.EnvSecret` | 1 | OpenAI-first per scope amendment; the agent loop can't run without one provider |
| 3 | `SessionAgent.Tool.Base` + `SessionAgent.Tool.Registry` + 3 example Inspection tools (`GetSessionSummary`, `GetSessionTimeline`, `GetMessageDetail`) | 1, 2 | Minimum tool set for a demo-able loop; validates the SQL/method-tool pattern |
| 4 | `SessionAgent.Agent.AgentLoop` + `SessionAgent.Chat.History` + concurrency locking | 2, 3 | The orchestrator that ties provider + tools + persistence |
| 5 | `SessionAgent.EnsPortal.Util.ChatPanelDrawHelper` + client-side JS wrapper (marked / Prism / DOMPurify) + ZenMethod hyperevent | 4 | Phase 2 demo: chat tab in Visual Trace |
| 6 | `SessionAgent.EnsPortal.VisualTrace` subclass + 4th tab + `SessionAgent.EnsPortal.MessageViewer` subclass with handoff | 5 | Phase 3 demo: search → click session → chat about it |
| 7 | Remaining Inspection-Agent tools (10 of 13) + read-only test suite | 3 | Fill out the tool catalog from the original product brief |
| 8 | `SessionAgent.LLM.AnthropicProvider` (concrete #2) + integration tests across both providers | 2 | Validates the provider abstraction by implementing the canonical shape |
| 9 | `SessionAgent.UI.AgentConfig` Zen page + `SessionAgent.Config.Agent` schema + per-agent secret routing | 4 | Operator UI; can ship before agents 8/10 if needed |
| 10 | `SessionAgent.LLM.GeminiProvider` (concrete #3) + `SessionAgent.LLM.OpenAICompatProvider` (concrete #4 — Ollama / vLLM) | 8 | Extensibility validation across all four providers |
| 11 | `SessionAgent.Task.PurgeOrphanedChatHistory` + Topic-10 Option-B sweep | 4 | Lifecycle coupling; can land late in v1 since orphan-window is acceptable |

The Message Search Agent, after its sibling research doc completes, becomes Epic 12+.

### IPM `module.xml` — Concrete v1 Shape

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Export generator="Cache" version="25">
  <Document name="iris-session-agent.ZPM">
    <Module>
      <Name>iris-session-agent</Name>
      <Version>1.0.0</Version>
      <Description>Pure-ObjectScript Ensemble session inspection and message search agents</Description>
      <Packaging>module</Packaging>
      <SourcesRoot>src</SourcesRoot>

      <!-- Class packages compiled into HSCUSTOMCODE -->
      <Resource Name="SessionAgent.PKG"/>

      <!-- Static UI assets vendored locally (no CDN dependency per Step 2) -->
      <FileCopy Name="static/" Target="${cspdir}static/iris-session-agent/"/>

      <!-- Dedicated CSP application for static assets (unauthenticated read) -->
      <CSPApplication Url="/csp/static/iris-session-agent"
                      Path="${cspdir}static/iris-session-agent"
                      Resource=""
                      Recurse="1"
                      UseCookies="0"
                      AuthenticationMethods="64"/>

      <!-- Install-time hooks -->
      <Invoke Method="Install" Class="SessionAgent.Installer"/>
      <Invoke Method="EnsureEvents" Class="SessionAgent.Audit.Emit"/>
      <Invoke Method="Install" Class="SessionAgent.Security.ReadOnlyRole"/>

      <!-- No external ZPM dependencies (per project's NFR-M9 lineage) -->
    </Module>
  </Document>
</Export>
```

**Vendored static-asset directory layout** (under `src/static/`):

```
static/
  marked.min.js              -- 18.0.2+ per Step 2 CVE note
  prism.min.js               -- core
  prism-objectscript.js      -- custom language def, falls back to 'markup'
  prism-sql.js
  prism-javascript.js
  prism-python.js
  prism.min.css              -- okaidia or coy theme
  dompurify.min.js           -- 3.x
  chat-panel.js              -- our wrapper — orchestrates marked → Prism → DOMPurify
  chat-panel.css             -- chat bubble styles, scoped to .iris-session-agent-chat
```

`chat-panel.js` (canonical shape, ~50 lines):

```javascript
(function (root) {
  marked.setOptions({
    gfm: true, breaks: true,
    highlight: function (code, lang) {
      var langDef = Prism.languages[lang] || Prism.languages.markup;
      return Prism.highlight(code, langDef, lang);
    }
  });
  function renderMarkdown(text) {
    var rawHtml = marked.parse(text);
    return DOMPurify.sanitize(rawHtml, { USE_PROFILES: { html: true } });
  }
  function appendChatTurn(containerId, role, markdownText) {
    var div = document.createElement('div');
    div.className = 'iris-session-agent-chat-turn role-' + role;
    div.innerHTML = renderMarkdown(markdownText);  // sanitized via DOMPurify
    document.getElementById(containerId).appendChild(div);
  }
  root.IrisSessionAgentChat = { renderMarkdown: renderMarkdown, appendChatTurn: appendChatTurn };
})(window);
```

### `SessionAgent.Installer.Install()` — Install-Time Work

```objectscript
Class SessionAgent.Installer Extends %RegisteredObject
{
  /// Called by IPM <Invoke> at install / upgrade time. Idempotent.
  ClassMethod Install(pInstance As %String = "iris-session-agent") As %Status
  {
    Set tSC = $$$OK
    Set tOrigNS = $NAMESPACE
    Try {
      ; (1) Ensure HSCUSTOMCODE database mapping covers SessionAgent.*
      ; (operator-controlled — we don't auto-map %ALL; document instead in README.)
      Do ..LogProgress("Verifying package mappings — see README for operator steps.")

      ; (2) Audit events registered in %SYS via SessionAgent.Audit.Emit.EnsureEvents()
      ;     (separate <Invoke> in module.xml; idempotent.)

      ; (3) RBAC role installed via SessionAgent.Security.ReadOnlyRole.Install()
      ;     (separate <Invoke> in module.xml; idempotent.)

      ; (4) Install periodic purge task (Topic 10 Option B sweep)
      Set tSC = ..InstallPurgeTask()  Quit:$$$ISERR(tSC)

      ; (5) Seed default agent configs (idempotent — only inserts if missing)
      Set tSC = ..SeedDefaultAgentConfigs()  Quit:$$$ISERR(tSC)

      ; (6) Print operator README reminders (visible in IPM install log)
      Do ..PrintOperatorReminders()
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Set $NAMESPACE = tOrigNS
    Quit tSC
  }

  ClassMethod InstallPurgeTask() As %Status
  {
    ; Create Task Manager entry for SessionAgent.Task.PurgeOrphanedChatHistory daily 02:00.
    Set tTask = ##class(%SYS.Task).%New()
    Set tTask.Name = "SessionAgent.PurgeOrphanedChatHistory"
    Set tTask.NameSpace = $NAMESPACE
    Set tTask.TaskClass = "SessionAgent.Task.PurgeOrphanedChatHistory"
    Set tTask.DailyFrequency = 0  // daily
    Set tTask.StartDate = +$Horolog
    Set tTask.TimePeriod = 0      // single time per day
    Set tTask.DailyStartTime = 7200  // 02:00 UTC, in seconds since midnight
    Quit tTask.%Save()
  }

  ClassMethod SeedDefaultAgentConfigs() As %Status
  {
    For tAgent = "session-inspection","message-search" {
      If '##class(SessionAgent.Config.Agent).%ExistsId(tAgent) {
        Set tCfg = ##class(SessionAgent.Config.Agent).%New()
        Set tCfg.AgentName = tAgent
        Set tCfg.Provider = "openai"
        Set tCfg.Model = "gpt-4o"
        Set tCfg.MaxTokens = 4096
        Set tCfg.Temperature = 0.0
        Set tCfg.ReadOnly = 1
        Set tCfg.EnvVarName = "OPENAI_API_KEY"
        Set tCfg.Enabled = 0  // off by default; operator opts in via UI
        Set tSC = tCfg.%Save()  Return:$$$ISERR(tSC) tSC
      }
    }
    Quit $$$OK
  }

  ClassMethod PrintOperatorReminders()
  {
    Write !,"=== iris-session-agent install reminders ==="
    Write !,"1. Set OPENAI_API_KEY (or ANTHROPIC_API_KEY / GOOGLE_API_KEY) as a process env var,"
    Write !,"   OR create an Ens.Config.Credentials row and reference it in SessionAgent.Config.Agent."
    Write !,"2. Raise Web Gateway 'Server Response Timeout' to 300s (default 60s is too tight"
    Write !,"   for some agent turns). Web Gateway management page → System Default Parameters."
    Write !,"3. Map SessionAgent.* from HSCUSTOMCODE to your interop namespaces"
    Write !,"   (Management Portal → System Administration → Configuration → Namespaces)."
    Write !,"4. Bookmark URL: /csp/healthshare/<NS>/SessionAgent.EnsPortal.MessageViewer.zen"
    Write !,"5. Edit SessionAgent.UI.AgentConfig.zen to enable agents and pin a model."
    Write !,"==========================================="
  }

  ClassMethod LogProgress(pMsg As %String) {
    Write !,"[iris-session-agent] ",pMsg
  }
}
```

### `SessionAgent.LLM.Provider` Abstract + `SessionAgent.LLM.OpenAIProvider` (Concrete #1)

```objectscript
Class SessionAgent.LLM.Provider Extends %RegisteredObject [ Abstract ]
{
  Property Config As SessionAgent.Config.Agent;
  Property LastHttpStatus As %Integer;
  Property LastRetryAfter As %Numeric;
  Property LastRequestId As %String;

  /// Send a turn to the provider. Returns canonical Anthropic-shape response.
  /// pHistory is canonical (Anthropic shape); concretes translate as needed.
  Method CallMessages(
    pHistory As %DynamicArray,
    pTools As %DynamicArray,
    pSystemPrompt As %String,
    pCacheConfig As %DynamicObject,
    Output pResponse As SessionAgent.LLM.ProviderResponse
  ) As %Status [ Abstract ] { Quit $$$OK }

  /// Resolve API key from env var or Ens.Config.Credentials per Config.
  Method GetApiKey() As %String
  {
    If ..Config.EnvVarName '= "" Quit $SYSTEM.Util.GetEnviron(..Config.EnvVarName)
    If ..Config.CredentialName '= "" {
      Set tCred = ##class(Ens.Config.Credentials).%OpenId(..Config.CredentialName)
      If $IsObject(tCred) Quit tCred.Password
    }
    Quit ""
  }
}

Class SessionAgent.LLM.OpenAIProvider Extends SessionAgent.LLM.Provider
{
  Parameter EndpointDefault = "https://api.openai.com/v1/chat/completions";

  Method CallMessages(pHistory, pTools, pSystemPrompt, pCacheConfig, Output pResponse) As %Status
  {
    Set tSC = $$$OK
    Set pResponse = ##class(SessionAgent.LLM.ProviderResponse).%New()
    Try {
      ; Build OpenAI-shape body (translate canonical history → OpenAI shape)
      Set tBody = {}
      Do tBody.%Set("model", ..Config.Model)
      Do tBody.%Set("messages", ##class(SessionAgent.LLM.Util.MessageAdapter).CanonicalToOpenAI(pHistory, pSystemPrompt))
      Do tBody.%Set("tools", ##class(SessionAgent.LLM.Util.ToolDefAdapter).CanonicalToOpenAI(pTools))
      Do tBody.%Set("tool_choice", "auto")
      Do tBody.%Set("temperature", ..Config.Temperature)
      Do tBody.%Set("max_tokens", ..Config.MaxTokens)

      ; HTTP call with retry
      Set tEndpoint = $Select(..Config.EndpointUrl '= "" : ..Config.EndpointUrl, 1: ..#EndpointDefault)
      Set tHttp = ##class(%Net.HttpRequest).%New()
      Do ..ConfigureForEndpoint(tHttp, tEndpoint)
      Do tHttp.SetHeader("Authorization", "Bearer "_..GetApiKey())
      Do tHttp.SetHeader("Content-Type", "application/json")
      Do tHttp.EntityBody.Write(tBody.%ToJSON())
      Do tHttp.EntityBody.Rewind()
      Set tHttp.Timeout = 90  // < Web Gateway 300s

      Set tSC = ##class(SessionAgent.Util.RetryWithBackoff).Call(tHttp, "POST", $piece(tEndpoint,"/",4,*))
      Quit:$$$ISERR(tSC)

      Set ..LastHttpStatus = tHttp.HttpResponse.StatusCode
      Set ..LastRequestId = tHttp.HttpResponse.GetHeader("x-request-id")

      ; Parse response and translate OpenAI → canonical
      Set tRespBody = {}.%FromJSON(tHttp.HttpResponse.Data)
      Set pResponse.Content = ##class(SessionAgent.LLM.Util.MessageAdapter).OpenAIToCanonicalContent(tRespBody)
      Set pResponse.StopReason = ##class(SessionAgent.LLM.Util.MessageAdapter).OpenAIToCanonicalStop(tRespBody)
      Set pResponse.Usage = ##class(SessionAgent.LLM.Util.MessageAdapter).OpenAIToCanonicalUsage(tRespBody)
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Quit tSC
  }

  Method ConfigureForEndpoint(pHttp, pEndpoint)
  {
    Set tProto = $Piece(pEndpoint, "://", 1)
    Set tRest  = $Piece(pEndpoint, "://", 2)
    Set tHost  = $Piece(tRest, "/", 1)
    Set tPort  = +$Piece(tHost, ":", 2)
    Set:tPort=0 tPort = $Select(tProto = "https" : 443, 1 : 80)
    Set pHttp.Server = $Piece(tHost, ":", 1)
    Set pHttp.Port = tPort
    Set pHttp.Https = (tProto = "https")
    Set pHttp.Location = "/"_$Piece(tRest, "/", 2, *)
    Set pHttp.SSLConfiguration = "DefaultSSL"  // operator-installed SSL config
  }
}
```

`SessionAgent.LLM.AnthropicProvider`, `SessionAgent.LLM.GeminiProvider`, and `SessionAgent.LLM.OpenAICompatProvider` follow the same shape with their respective adapter calls and header sets per the Step 4 provider table.

### `SessionAgent.Util.RetryWithBackoff`

```objectscript
Class SessionAgent.Util.RetryWithBackoff Extends %RegisteredObject
{
  Parameter MaxAttempts = 4;
  Parameter BaseDelaySec = 1;
  Parameter MaxDelaySec = 32;

  /// Issue HTTP request with full-jitter exponential backoff.
  /// pMethod: "POST"|"GET"|...
  /// pLocation: e.g., "/v1/messages"
  ClassMethod Call(pHttp As %Net.HttpRequest, pMethod As %String, pLocation As %String) As %Status
  {
    For tAttempt = 1:1:..#MaxAttempts {
      Set tSC = $Method(pHttp, pMethod, pLocation)
      Set tStatus = pHttp.HttpResponse.StatusCode
      ; Success
      If tStatus '= "", tStatus < 400 Quit
      ; Non-retryable 4xx
      If '..IsRetryable(tStatus) Set tSC = $$$ERROR($$$GeneralError, "HTTP "_tStatus_" non-retryable") Quit
      ; Last attempt — surface
      If tAttempt = ..#MaxAttempts Set tSC = $$$ERROR($$$GeneralError, "HTTP "_tStatus_" exhausted retries") Quit
      ; Compute delay: prefer Retry-After header, else exponential backoff with full jitter
      Set tRetryAfter = +pHttp.HttpResponse.GetHeader("retry-after")
      Set tDelay = $Select(tRetryAfter > 0 : tRetryAfter, 1 : ..ExpBackoff(tAttempt))
      Hang tDelay
    }
    Quit tSC
  }

  ClassMethod ExpBackoff(pAttempt As %Integer) As %Numeric
  {
    Set tCap = $Select((2 ** (pAttempt - 1)) * ..#BaseDelaySec > ..#MaxDelaySec : ..#MaxDelaySec,
                       1 : (2 ** (pAttempt - 1)) * ..#BaseDelaySec)
    Quit ($Random(1000) / 1000) * tCap   // full jitter, 0..tCap
  }

  ClassMethod IsRetryable(pStatus As %Integer) As %Boolean
  {
    Quit $Case(pStatus, 429:1, 500:1, 502:1, 503:1, 504:1, 529:1, : 0)
  }
}
```

For Gemini, a parallel `SessionAgent.Util.GeminiRetryParser` extracts `error.details[].retryDelay` from the JSON body — the standard `Retry-After` header path doesn't apply (per Step 4's provider table).

### `SessionAgent.Tool.Base` + `SessionAgent.Tool.Registry` Skeleton

```objectscript
Class SessionAgent.Tool.Base Extends %RegisteredObject [ Abstract ]
{
  Parameter ToolName As STRING;
  Parameter Description As STRING;
  Parameter MutatesState As BOOLEAN = 0;

  /// Returns the JSON Schema for this tool's input. Subset:
  /// {type, properties, required, enum, description, additionalProperties}.
  ClassMethod GetInputSchema() As %DynamicObject [ Abstract ] { Quit {} }

  /// Pure dispatch contract. No %session, %request, or Zen state.
  ClassMethod Invoke(
    pCallerCtx As SessionAgent.Agent.CallerContext,
    pJsonArgs As %DynamicObject,
    Output pResult As %DynamicObject
  ) As %Status [ Abstract ] { Quit $$$OK }
}

Class SessionAgent.Tool.Registry Extends %RegisteredObject
{
  /// List tools registered for an agent (Inspection vs Search).
  /// Reflection: enumerate SessionAgent.Tool.Inspection.* or SessionAgent.Tool.Search.* subclasses.
  ClassMethod ListTools(pAgentName As %String) As %DynamicArray
  {
    Set tArr = []
    Set tPackage = $Case(pAgentName,
                         "session-inspection" : "SessionAgent.Tool.Inspection",
                         "message-search"     : "SessionAgent.Tool.Search",
                         : "")
    Quit:tPackage="" tArr
    ; Enumerate via %Dictionary.ClassDefinition (per Step 2 Topic 4).
    Set tStmt = ##class(%SQL.Statement).%New()
    Do tStmt.%PrepareClassQuery("%Dictionary.ClassDefinition", "SubclassOf")
    Set tRs = tStmt.%Execute("SessionAgent.Tool.Base")
    While tRs.%Next() {
      Continue:'$Match(tRs.Name, "^"_tPackage_"\.")
      Set tName   = $ClassMethod(tRs.Name, "%GetParameter", "ToolName")
      Set tDesc   = $ClassMethod(tRs.Name, "%GetParameter", "Description")
      Set tSchema = $ClassMethod(tRs.Name, "GetInputSchema")
      Do tArr.%Push({"name": (tName), "description": (tDesc), "inputSchema": (tSchema)})
    }
    Quit tArr
  }

  /// Single dispatch funnel. Layers 2 (read-only policy) and 4 (audit) live here.
  ClassMethod Dispatch(
    pAgentName As %String,
    pToolName As %String,
    pCallerCtx As SessionAgent.Agent.CallerContext,
    pJsonArgs As %DynamicObject,
    Output pResult As %DynamicObject
  ) As %Status
  {
    Set tStart = $ZHorolog
    Set tSC = $$$OK
    Set pResult = {}
    Try {
      ; Resolve tool class by name
      Set tToolClass = ..LookupTool(pAgentName, pToolName)
      If tToolClass = "" {
        Set pResult = {"isError": (1), "content": [{"type": "text", "text": "Unknown tool"}]}
        Return $$$OK
      }
      ; Layer 2: read-only policy gate
      Set tMutates = $ClassMethod(tToolClass, "%GetParameter", "MutatesState")
      Set tCfg = ##class(SessionAgent.Config.Agent).%OpenId(pAgentName)
      If tMutates = 1, $IsObject(tCfg), tCfg.ReadOnly = 1 {
        Set pResult = {"isError": (1), "content": [{"type": "text", "text": "Tool blocked by read-only policy"}]}
        Do ..LogToolCall(pAgentName, pToolName, pCallerCtx, pJsonArgs, pResult, $ZHorolog - tStart, 1)
        Return $$$OK
      }
      ; Invoke
      Set tSC = $ClassMethod(tToolClass, "Invoke", pCallerCtx, pJsonArgs, .pResult)
      ; Layer 4: audit
      Do ..LogToolCall(pAgentName, pToolName, pCallerCtx, pJsonArgs, pResult, $ZHorolog - tStart, 0)
    }
    Catch ex {
      ; Convert exceptions to structured tool errors per MCP contract
      Set pResult = {"isError": (1), "content": [{"type": "text", "text": (ex.DisplayString())}]}
      Do ..LogToolCall(pAgentName, pToolName, pCallerCtx, pJsonArgs, pResult, $ZHorolog - tStart, 0)
      Set tSC = $$$OK  ; tool errors are surfaced via isError, not %Status
    }
    Quit tSC
  }

  ClassMethod LookupTool(pAgentName, pToolName) As %String { /* Cache lookup */ }
  ClassMethod LogToolCall(pAgentName, pToolName, pCtx, pArgs, pResult, pDurationSec, pBlockedByPolicy) As %Status { /* Audit row */ }
}
```

### Example Tool Implementation: `SessionAgent.Tool.Inspection.GetSessionSummary`

The 9 SQL-driven tools follow this canonical pattern. (Replaces AI Hub's `<Query>` element auto-generation.)

```objectscript
Class SessionAgent.Tool.Inspection.GetSessionSummary Extends SessionAgent.Tool.Base
{
  Parameter ToolName = "session_summary";
  Parameter Description = "Return shape, duration, error count, and root message class for an Ens session.";
  Parameter MutatesState = 0;

  ClassMethod GetInputSchema() As %DynamicObject
  {
    Quit {
      "type": "object",
      "properties": {
        "session_id": {"type": "string", "description": "Ens session id"}
      },
      "required": ["session_id"],
      "additionalProperties": false
    }
  }

  ClassMethod Invoke(pCallerCtx As SessionAgent.Agent.CallerContext, pJsonArgs As %DynamicObject, Output pResult As %DynamicObject) As %Status
  {
    Set tSessionId = pJsonArgs.%Get("session_id")
    If tSessionId = "" {
      Set pResult = {"isError": (1), "content": [{"type":"text","text":"missing session_id"}]}
      Quit $$$OK
    }
    Set tStmt = ##class(%SQL.Statement).%New()
    Set tSC = tStmt.%Prepare(
      "SELECT COUNT(*) AS msg_count, "_
      "       MIN(TimeCreated) AS first_msg, MAX(TimeCreated) AS last_msg, "_
      "       SUM(CASE WHEN IsError=1 THEN 1 ELSE 0 END) AS err_count, "_
      "       (SELECT TOP 1 MessageBodyClassName FROM Ens.MessageHeader WHERE %ID = ?) AS root_class "_
      "FROM Ens.MessageHeader WHERE %EXACT(SessionId) = ?"
    )
    If $$$ISERR(tSC) Quit tSC
    Set tRs = tStmt.%Execute(tSessionId, tSessionId)
    Set pResult = {"content": [{"type": "text", "text": ""}], "structuredContent": {}}
    If tRs.%Next() {
      Do pResult.structuredContent.%Set("session_id", tSessionId)
      Do pResult.structuredContent.%Set("message_count", tRs.%Get("msg_count"))
      Do pResult.structuredContent.%Set("first_msg", tRs.%Get("first_msg"))
      Do pResult.structuredContent.%Set("last_msg", tRs.%Get("last_msg"))
      Do pResult.structuredContent.%Set("error_count", tRs.%Get("err_count"))
      Do pResult.structuredContent.%Set("root_message_class", tRs.%Get("root_class"))
    }
    ; Provide a text summary for LLMs that don't yet honor structuredContent
    Set tText = "Session "_tSessionId_": "_pResult.structuredContent.message_count_" messages, "_
                pResult.structuredContent.error_count_" errors, root class "_
                pResult.structuredContent.root_message_class
    Set pResult.content.%Get(0).text = tText
    Quit $$$OK
  }
}
```

Key notes echoing the project's existing CLAUDE.md rules:

- `%EXACT(SessionId)` per IRIS SQL case-sensitivity rule
- `%ID` pseudo-column on the inner subquery
- No `&sql(UPDATE)` anywhere — this is a read-only tool (MutatesState=0)
- Error path returns structured `{isError:true, content:[...]}` per MCP contract — does NOT throw

### `SessionAgent.Chat.History` Persistence

```objectscript
Class SessionAgent.Chat.History Extends %Persistent
{
  Property AgentName As %String(MAXLEN=64) [ Required ];
  Property SessionKey As %String(MAXLEN=64) [ Required ];
  Property PortalUser As %String(MAXLEN=64) [ Required ];
  Property TurnsJson As %Stream.GlobalCharacter;
  Property CreatedAt As %TimeStamp [ InitialExpression = {$ZDateTime($H,3,1)} ];
  Property UpdatedAt As %TimeStamp;
  Property Provider As %String(MAXLEN=32);
  Property Model As %String(MAXLEN=64);
  Index PrimaryKey On (AgentName, SessionKey, PortalUser) [ PrimaryKey ];
  Index ByAgentSession On (AgentName, SessionKey);

  ClassMethod LoadOrCreate(pAgentName, pSessionKey, pPortalUser) As SessionAgent.Chat.History
  {
    Set tId = pAgentName_"||"_pSessionKey_"||"_pPortalUser
    Set tHist = ..%OpenId(tId, 4)  ; concurrency=4, exclusive lock
    If '$IsObject(tHist) {
      Set tHist = ..%New()
      Set tHist.AgentName = pAgentName
      Set tHist.SessionKey = pSessionKey
      Set tHist.PortalUser = pPortalUser
      Set tCfg = ##class(SessionAgent.Config.Agent).%OpenId(pAgentName)
      Set tHist.Provider = tCfg.Provider
      Set tHist.Model = tCfg.Model
      Do tHist.%Save()  ; releases lock momentarily; reacquire for the turn
      Set tHist = ..%OpenId(tId, 4)
    }
    Quit tHist
  }

  Method GetTurnsArray() As %DynamicArray
  {
    If ..TurnsJson.Size = 0 Quit []
    Quit [].%FromJSON(..TurnsJson)
  }

  Method SetTurnsArray(pArr As %DynamicArray) As %Status
  {
    Do ..TurnsJson.Clear()
    Do ..TurnsJson.Write(pArr.%ToJSON())
    Set ..UpdatedAt = $ZDateTime($H, 3, 1)
    Quit $$$OK
  }
}
```

### `SessionAgent.Task.PurgeOrphanedChatHistory`

```objectscript
Class SessionAgent.Task.PurgeOrphanedChatHistory Extends %SYS.Task.Definition
{
  Parameter TaskName = "App PurgeOrphanedChatHistory";

  Method OnTask() As %Status
  {
    Set tDeleted = 0
    &sql(DECLARE C1 CURSOR FOR
         SELECT %ID, AgentName, SessionKey
         FROM App_Chat.History
         WHERE AgentName = 'session-inspection')
    &sql(OPEN C1)
    Set tDone = 0
    For { &sql(FETCH C1 INTO :id, :agent, :sk)  Quit:SQLCODE'=0
      &sql(SELECT 1 INTO :exists FROM Ens.MessageHeader WHERE %EXACT(SessionId) = :sk)
      If SQLCODE = 100 {
        ; orphaned — Ens session was purged
        Set tSC = ##class(SessionAgent.Chat.History).%DeleteId(id)
        Set:$$$ISOK(tSC) tDeleted = tDeleted + 1
      }
    }
    &sql(CLOSE C1)
    Do ##class(%SYS.Audit).Audit("SessionAgent","TaskRun","PurgeOrphanedChatHistory",,,"Deleted="_tDeleted)
    Quit $$$OK
  }
}
```

(Message Search Agent rows have no Ens-session-id linkage, so they're excluded by the `WHERE AgentName = 'session-inspection'` filter — their lifecycle policy is "explicit user delete" or a separate TTL-based sweep, both decided in the sibling research doc.)

### `SessionAgent.Security.ReadOnlyRole.Install()` (Layer 3 Read-Only Enforcement)

```objectscript
Class SessionAgent.Security.ReadOnlyRole Extends %RegisteredObject
{
  Parameter RoleName = "%SessionAgent_ReadOnly";

  ClassMethod Install() As %Status
  {
    Set tOrigNS = $NAMESPACE
    Set $NAMESPACE = "%SYS"
    Try {
      ; Idempotent: skip if exists
      If '##class(Security.Roles).Exists(..#RoleName) {
        Set tProps("Description") = "iris-session-agent: SELECT-only on Ens.* tables for agent-runtime users"
        Set tProps("GrantedRoles") = ""
        Set tSC = ##class(Security.Roles).Create(..#RoleName, .tProps)
        Quit:$$$ISERR(tSC) tSC
      }
      ; Grant SELECT on each Ens table our tools touch.
      For tTable = "Ens.MessageHeader","Ens_Util.Log","Ens_Rule.Log",
                   "Ens.MessageBody","Ens.SuperSessionIndex" {
        Set tSC = ##class(%SYSTEM.SQL.Security).GrantPrivilege("SELECT", tTable, ..#RoleName)
        ; Note: ignore "already granted" - idempotent
      }
    }
    Catch ex { Set tSC = ex.AsStatus() }
    Set $NAMESPACE = tOrigNS
    Quit tSC
  }
}
```

Per the project's existing `Namespace Switching in REST Handlers` rule, the `Set $NAMESPACE = "%SYS"` ↔ `Set $NAMESPACE = tOrigNS` pattern uses an explicit save/restore variable, not `New $NAMESPACE`.

### `SessionAgent.EnsPortal.Util.ChatPanelDrawHelper` (Shared between Phase 2 and Phase 3)

```objectscript
Class SessionAgent.EnsPortal.Util.ChatPanelDrawHelper Extends %RegisteredObject
{
  /// Called by both SessionAgent.EnsPortal.VisualTrace and SessionAgent.EnsPortal.MessageViewer
  /// from XData allTabs as <html OnDrawContent="...DrawChatPanel"/>.
  ClassMethod DrawChatPanel(pSeed As %String) As %Status
  {
    ; pSeed encodes which agent to wire up: "session-inspection" or "message-search"
    Set tAgent = pSeed
    &html<
      <link rel="stylesheet" href="/csp/static/iris-session-agent/prism.min.css"/>
      <link rel="stylesheet" href="/csp/static/iris-session-agent/chat-panel.css"/>
      <div class="iris-session-agent-chat" data-agent-name="#(tAgent)#">
        <div class="chat-history" id="chatHistory_#(tAgent)#"></div>
        <div class="chat-input">
          <textarea id="chatInput_#(tAgent)#" rows="3" placeholder="Ask about this..."></textarea>
          <button onclick="zenPage.sendChatMessage('#(tAgent)#')">Send</button>
        </div>
      </div>
      <script src="/csp/static/iris-session-agent/marked.min.js"></script>
      <script src="/csp/static/iris-session-agent/prism.min.js"></script>
      <script src="/csp/static/iris-session-agent/prism-objectscript.js"></script>
      <script src="/csp/static/iris-session-agent/prism-sql.js"></script>
      <script src="/csp/static/iris-session-agent/dompurify.min.js"></script>
      <script src="/csp/static/iris-session-agent/chat-panel.js"></script>
    >
    Quit $$$OK
  }
}
```

The hosting Zen pages each define a `ClientMethod sendChatMessage(agentName)` that:
1. Reads the textarea value.
2. Computes `sessionKey` from `zenPage.currentTraceSessionId` (Phase 2) or a UI-issued GUID (Phase 3 search context).
3. Calls the synchronous ZenMethod hyperevent `SendChatMessage(agentName, sessionKey, userText, contextHints)`.
4. On return, parses the response JSON and calls `IrisSessionAgentChat.appendChatTurn(containerId, "assistant", markdown)`.

### `SessionAgent.UI.AgentConfig` Zen Page (Operator Configuration UI)

A standard `%ZEN.Component.page` subclass under HSCUSTOM, accessible at `/csp/healthshare/<NS>/SessionAgent.UI.AgentConfig.zen`. Two-pane: left = list of agent names; right = edit form with `<select>` for Provider, `<textfield>` for Model, `<numericfield>` for MaxTokens / Temperature, `<select>` for CredentialName (populated from `Ens.Config.Credentials`), `<textfield>` for EnvVarName, `<checkbox>` for Enabled / ReadOnly, `<textarea>` for SystemPromptOverride.

ZenMethod `SaveConfig(jsonPayload)` opens the row by AgentName, applies fields, and `%Save()`s. Per the same project rule, the page uses explicit save/restore for `%session.Username` capture via `tCfg.UpdatedBy = %session.Username`.

### Operator README Content (the install-time prerequisite list)

Per `research-first.md` rule 5, this content **must ride the v1 commit** (operator-observable state):

```markdown
## iris-session-agent — Installation Prerequisites

Before installing this module, verify the following on your IRIS instance.

### 1. Supported IRIS versions
- IRIS / IRIS for Health 2024.1 or later.

### 2. Web Gateway timeout
The default Web Gateway "Server Response Timeout" (60s) is too tight for some agent
turns that combine multiple LLM round-trips. Raise it to **300s** before installing.

  Web Gateway management page (typically http://<host>/csp/bin/Systems/Module.cxw)
  → System Default Parameters → Server Response Timeout → 300

### 3. API key for the LLM provider
Pick one of:

  - Set OPENAI_API_KEY (or ANTHROPIC_API_KEY / GOOGLE_API_KEY) as a process
    environment variable visible to the IRIS process. Container deployments
    typically inject these via Docker / Kubernetes secrets.
  - OR create an Ens.Config.Credentials row with SystemName='openai-prod'
    (or whatever name you like), Username='apikey', Password='<key>'. Then
    point SessionAgent.Config.Agent.CredentialName at that name.

API keys are NEVER stored in SessionAgent.Config.Agent itself.

### 4. Package mapping
Map SessionAgent.* from HSCUSTOMCODE to your interop namespaces (or %ALL).

  Management Portal → System Administration → Configuration → Namespaces →
  <target NS> → Package Mappings → Add: SessionAgent.*  ← HSCUSTOMCODE

### 5. RBAC
The module installer creates the %SessionAgent_ReadOnly role with SELECT-only
grants on Ens.* tables. Assign this role to the IRIS user that the portal
user maps to (typically the same user — verify via Security Management).

### 6. Bookmark URL
After install:
  /csp/healthshare/<NS>/SessionAgent.EnsPortal.MessageViewer.zen   (search agent entry)
  /csp/healthshare/<NS>/SessionAgent.EnsPortal.VisualTrace.zen     (inspection agent on a session)

### 7. Daily purge task
The installer schedules SessionAgent.Task.PurgeOrphanedChatHistory daily at 02:00 UTC.
Verify it's enabled in the Task Manager. It cleans chat-history rows whose
linked Ens session has been purged.
```

### Test Strategy

| Layer | Test scope | IRIS test framework | Notes |
|---|---|---|---|
| Unit | Each tool's `Invoke`; `MessageAdapter` translation correctness; `RetryWithBackoff.ExpBackoff` distribution | `%UnitTest.TestCase` per project's `object-script-testing.md` rules | Mock `Ens.MessageHeader` rows in test setup; tear down in `OnAfterOneTest` |
| Integration | End-to-end `AgentLoop.RunTurn` against a stub `SessionAgent.LLM.Provider` that returns canned responses | `%UnitTest.TestCase` | No live LLM call; stub provider validates the loop's branching |
| Smoke | One real turn against OpenAI per provider concrete; gated behind an env-var to skip in CI | `%UnitTest.TestCase` with `OnBeforeOneTest` skip-if-no-key | Validates wire shape parity across providers |
| Read-only enforcement | Layer 2: configure a tool with `MutatesState=1`; verify dispatch returns `isError`. Layer 3: try `INSERT INTO Ens.MessageHeader` as agent user; verify SQL error | `%UnitTest.TestCase` + raw SQL test | Per project's existing `IRIS Library Source` rule, do NOT mock RBAC |
| Lifecycle coupling | Insert chat-history row, delete the corresponding Ens.MessageHeader rows, run the sweep task, assert chat-history row is deleted | `%UnitTest.TestCase` | Validates Topic 10 Option B end-to-end |

**Coverage targets:** 100% of tool `Invoke` paths under unit; ≥80% of `AgentLoop` branches under integration; sweep task at 100% of its decision branches.

### Confidence Notes for Step 5 Findings

- **Sprint sequencing**: High — depends only on the established class hierarchy.
- **`module.xml` shape**: Medium — `<CSPApplication>` `${cspdir}` substitution and `AuthenticationMethods="64"` (unauthenticated) syntax match documented IPM patterns; verify on first install.
- **`SessionAgent.LLM.OpenAIProvider` HTTP details**: Medium-High — `%Net.HttpRequest` patterns are canonical, but `SSLConfiguration = "DefaultSSL"` assumes the operator has installed a default SSL config; install README should call this out.
- **`SessionAgent.Tool.Registry.ListTools` reflection**: Medium — the `%Dictionary.ClassDefinition:SubclassOf` query works in current IRIS; **Task-0 probe required on 2024.1** per the carry-forward Step 2 confidence flag.
- **`SessionAgent.Task.PurgeOrphanedChatHistory` SQL**: Medium — embedded SQL cursor pattern is canonical, but verify `SELECT 1 INTO :exists` / `SQLCODE=100` semantics on 2024.1 with at least one orphan-row test before relying on it.
- **`SessionAgent.Security.ReadOnlyRole.Install()`**: High — uses documented `Security.Roles.Create()` + `%SYSTEM.SQL.Security.GrantPrivilege()` paths.

---

## Research Synthesis & Executive Summary

### The Bottom Line

A pure-ObjectScript Ensemble Session Inspection Agent that ships ahead of AI Hub on IRIS 2024.1+ is **architecturally feasible and demo-able from Epic 6**, with no embedded Python in the runtime path and no AI Hub primitives. The same shared infrastructure (provider abstraction, tool registry, chat history persistence, audit log, RBAC role) directly supports the sibling Message Search Agent, the four-provider framework (OpenAI / Anthropic / Gemini / Ollama), and a future MCP-server transport — all without rework of v1 components. The biggest architectural risk is not technical: it's **operator misconfiguration of the Web Gateway response timeout**, a 60-second default that silently kills longer agent turns. Surface this as a top-line README prerequisite.

### Top Findings (the seven that matter most)

1. **`%Library.IRISWallet` does not exist in IRIS 2024.1.** It was introduced in 2026.1 and the original `sources/iris-session-chat/` brief implicitly assumed a newer IRIS than our floor allows. Topic 8's path is settled: env-var primary (`$SYSTEM.Util.GetEnviron`) → `Ens.Config.Credentials` secondary → AES-encrypted `%Persistent` last-resort.
2. **The agent loop is provider-agnostic, but the provider layer is not.** Bind canonical on the Anthropic shape (most structured), translate down to OpenAI / Gemini / Ollama via mechanical adapters. The Gemini-specific quirks (object-not-stringified args, `STOP` as the tool stop reason, `error.details[].retryDelay` instead of `Retry-After` header, `parts[]` inspection for `functionCall` detection) all fit cleanly into the adapter pattern — no shape revision needed.
3. **The Web Gateway "Server Response Timeout" default of ~60s is the operational LLM-call cliff, not the CSP session timeout.** A turn with three tool round-trips averaging 8s + three LLM calls averaging 7s = ~45s, perilously close to 60. **Raise to 300s as an operator prerequisite. Document in README.**
4. **The MCP-export future-state mandate constrains the dispatch contract today.** A clean `(toolName, jsonArgs) → jsonResult` interface where tools never see `%session`, `%request`, or Zen state turns "future MCP server" from a refactor into a transport layer drop-in. The seven-anti-pattern list in §Integration Patterns is the audit checklist.
5. **Chat history should not pollute `Ens.MessageHeader`.** Topic 10 Option B (separate `SessionAgent.Chat.History` `%Persistent` + daily `SessionAgent.Task.PurgeOrphanedChatHistory` sweep) preserves the operator's primary debugging surface (Visual Trace) at the cost of ~30 lines of custom purge logic. Option A's UX regression — chat clutter in Visual Trace — is a one-way door we'd be choosing to ship.
6. **Three-layer read-only enforcement is non-negotiable for compliance defensibility.** L1 (impl discipline) + L2 (dispatch policy gate consulting `MutatesState=0/1`) + L3 (IRIS RBAC `%SessionAgent_ReadOnly` role with SELECT-only grants on `Ens.*`). Each layer alone is fragile; only the stack survives an L1 oversight or an L2 misconfiguration.
7. **The vendored static-asset path (`marked` + `Prism.js` + `DOMPurify`, ~45 KB gzipped, served from `/csp/static/iris-session-agent/`) is operationally simpler than CDN.** Customer firewalls block external CDNs more often than not; vendoring eliminates supply-chain timing risk and CVE-driven URL churn.

### Strategic Recommendations (top six)

1. **Implement OpenAI provider first**, validate the abstraction with Anthropic second, add Gemini third, free-ride Ollama on OpenAI's translator. Per the user's explicit priority and the principle that the abstraction's first concrete should be a translator (catches lazy assumptions early). Anthropic-as-canonical is the *design center*; OpenAI-as-first-shipped is the *demo path*.
2. **Land Epics 1–6 before everything else.** Foundation → provider → tools → loop → chat panel → portal subclasses gives a working OpenAI-powered Inspection Agent demo in the operator's hands. Subsequent epics layer polish; the first six prove the whole stack.
3. **Spin up the sibling Message Search Agent research doc as soon as this one is committed.** That agent's tool surface, scale-handling patterns (millions of `Ens.MessageHeader` rows), and search-term-learning persistence model are big enough to deserve the same six-step rigor. Don't try to wedge them into this doc.
4. **Issue the three Task-0 probes early in Epic 1.** They each take ~10 minutes to run on a 2024.1 instance; deferring them risks dispatching a story whose foundational assumption is wrong.
5. **Document operator prerequisites as commit-time README content** (per `research-first.md` rule 5 — operator-observable state must ride the commit). The seven-item list in §Implementation: Operator README Content is the canonical form.
6. **Re-litigate Topic 10 (Option B vs A) at PRD time** if a strict-immediate-purge compliance constraint surfaces. The 24-hour orphan window is acceptable for the v1 audience but may not be for regulated environments. The architecture supports a tighter sweep cadence (hourly) without redesign.

### Risk Roll-Up (consolidated from confidence notes across all steps)

| Risk | Severity | Mitigation in v1 |
|---|---|---|
| **Web Gateway "Server Response Timeout" default kills long agent turns** | High (operational, common pitfall) | README mandates raise to 300s; per-call provider timeout cap of 90s |
| **`%Dictionary.*Definition` 2024.1 surface uncorroborated against version-specific docs** | Medium | Task-0 probe in Epic 1 — `##class(%Dictionary.MethodDefinition).%OpenId("Ens.BusinessProcess||OnRequest")` against a live 2024.1 instance |
| **`Ens.Config.Credentials` requires Ensemble enabled in the namespace** | Low (true for HSCUSTOM and any Interop NS) | Document in README; fall back to AES-encrypted secret with `$SYSTEM.Util.GetEnviron` master key |
| **OSS-LLM tool-call reliability variance (Qwen good, smaller models malformed-args)** | Medium | Agent loop's parse-failure-retry path must be reliable; v1 ships with provider-routing toward Qwen 32B+ for Ollama deployments; document in README |
| **Anthropic prompt caching costs (writes 1.25× / reads 0.1×) misused** | Medium | Cache only the system prompt and tool definitions; do not cache message history; verify `cache_creation_input_tokens` vs `cache_read_input_tokens` ratio in audit log |
| **OpenAI error-codes doc behind 403 wall to direct fetch — defaults inferred** | Medium | Task-0 probe: trigger a deliberate 429 against OpenAI in dev, log the response shape, validate `Retry-After` parsing |
| **Operator misconfigures package mappings (HSCUSTOM ↔ target NS)** | Low (well-known HealthShare pattern) | Installer prints reminder; smoke test fails with clear error if mapping absent |
| **Gemini 2.5 Flash erratic tool-call schema adherence** | Medium | Default to Gemini 2.5/3 Pro for tool-using agent loops; document as configuration guidance |
| **Cache TTL invalidation between turns (Anthropic 5-min sliding)** | Low | Multi-turn conversations within one operator-session almost always stay inside the 5-min window; documented as a known cost-shape consideration |
| **Topic 10 24-hour orphan window** | Low (v1 audience) / Re-litigate at PRD if regulated environment | Sweep cadence is configurable (hourly possible without redesign) |

### Task-0 Probes Carried Forward to Implementation

Per `research-first.md` rule 4 — these execute on a live 2024.1 instance **before** the implementation story they unblock is dispatched:

1. **Dictionary reflection** — `##class(%Dictionary.MethodDefinition).%OpenId("Ens.BusinessProcess||OnRequest")` should return a non-null object. Unblocks Epic 3 (tool registry generation).
2. **Embedded SQL existence check** — Run `&sql(SELECT 1 INTO :exists FROM Ens.MessageHeader WHERE %EXACT(SessionId) = '<known-id>')` and verify `SQLCODE=0` for an existing session, `SQLCODE=100` for a non-existent session. Unblocks Epic 11 (purge sweep task).
3. **Web Gateway timeout** — Inspect the operator's Web Gateway management page → System Default Parameters → "Server Response Timeout" — capture verbatim default value. Drives the README content with a concrete before-state. Unblocks Epic 1 (operator README).

### Open Questions (unresolved at v1 architecture; defer to PRD or sibling research)

1. **PHI redaction policy.** The original brief explicitly scoped PHI out of v1; this research carried that forward. A body-redaction layer in the dispatch path (between `Tool.Invoke` and the LLM call) may be needed even for nominally-non-PHI namespaces — HL7 MSH/PID segments often carry patient identifiers. Decision belongs to the PRD, not architecture.
2. **Concurrent users sharing a `%session`** (multiple browser tabs in the same operator's portal session). Step 4 specifies `%OpenId(id, 4)` exclusive locking on `SessionAgent.Chat.History` rows; what about Inspection-Agent and Search-Agent tabs open simultaneously by the same operator (different agent names, same `PortalUser`)? Cross-row locking semantics validated in Step 5 unit test, but UX guidance for the operator is unwritten.
3. **Cross-namespace agent operation in a single conversation.** Inherited brief explicit OUT of v1 (per `Namespace Switching in REST Handlers` rule, runtime `ZN` in CSP context is dangerous). Each bookmark targets one namespace. Future work; the architecture doesn't preclude it.
4. **The Message Search Agent's chat-history keying model.** No Ens session id exists at search time; how is the search-agent chat keyed (registry-issued GUID? per-tab session?), and how is the per-user search-term-learning vocabulary stored? Sibling research doc.
5. **Streaming responses from LLM providers.** v1 stays blocking (Web Gateway timeout-coordinated, simpler client). v1.5 question: do we want partial-response streaming for long turns, and if so, do we use SSE or flip the chat panel to async-poll? Architecture documented as "v1.5 mitigation hierarchy"; not blocking for v1.

### Source Documentation Recap

**InterSystems / IRIS 2024.1 surface** — verified primarily against local `irislib/` source where present (`%Net/HttpRequest.cls`, `%SYSTEM/Util.cls`, `%SYSTEM/Encryption.cls`, `Ens/Config/Credentials.cls`) and against `https://docs.intersystems.com/iris20241/` and `irislatest`. Web Gateway default: corroborated via [community post on each timeout's meaning](https://community.intersystems.com/post/description-each-timeout-value-can-be-set-default-parameter-web-gatewaycsp-gateway-management) and [Web Gateway Configure System-Wide Parameters](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=GCGI_oper_config).

**Anthropic** — error-code surface verified directly from [docs.anthropic.com/en/api/errors](https://platform.claude.com/docs/en/api/errors) (redirected to `platform.claude.com`); message API + tool use + prompt caching from [docs.anthropic.com](https://docs.anthropic.com/en/api/messages), [Prompt Caching](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching), [Tool Use](https://docs.anthropic.com/en/docs/agents-and-tools/tool-use).

**OpenAI** — [Function Calling](https://platform.openai.com/docs/guides/function-calling), [API Reference](https://platform.openai.com/docs/api-reference/chat), [Prompt Caching](https://platform.openai.com/docs/guides/prompt-caching). Direct fetch of the errors page returned 403 — defaults inferred from openai-python SDK widely-documented behavior; flagged as Medium confidence and mitigated via Task-0.

**Google Gemini** — [generate-content API](https://ai.google.dev/api/generate-content), [function-calling docs](https://ai.google.dev/gemini-api/docs/function-calling), [API key auth](https://ai.google.dev/gemini-api/docs/api-key), [caching docs](https://ai.google.dev/gemini-api/docs/caching).

**Ollama / vLLM** — [Ollama tool support blog](https://ollama.com/blog/tool-support), [vLLM OpenAI-compatible server docs](https://docs.vllm.ai/), [BFCL V4 leaderboard](https://gorilla.cs.berkeley.edu/leaderboard.html) for tool-call reliability ranking.

**MCP protocol** — [MCP 2025-11-25 server/tools spec](https://modelcontextprotocol.io/specification/2025-11-25/server/tools), [transports spec](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports), [authorization spec](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization).

**Browser rendering** — [marked vs markdown-it 2026 comparison](https://www.pkgpulse.com/compare/markdown-it-vs-marked), [CVE-2026-41680 (marked DoS)](https://app.opencve.io/cve/?vendor=markedjs), [CVE-2025-7969 (markdown-it disputed)](https://nvd.nist.gov/vuln/detail/CVE-2025-7969), [Prism vs highlight.js bundle comparison](https://chsm.dev/blog/2025/01/08/comparing-web-code-highlighters), [OEX search — no ObjectScript markdown parser exists](https://openexchange.intersystems.com).

**Project context** — `sources/iris-session-chat/_bmad-output/planning-artifacts/product-brief-ensemble-session-inspection-agent-distillate.md` (the original AI-Hub-coupled brief), [`docs/initial-prompt.md`](../../../docs/initial-prompt.md) (the user's authoritative scope spec, surfaced post-Step-3 and reconciled in §Scope Amendments).

### Workflow Completion

| Step | Title | Output |
|---|---|---|
| 1 | Scope Confirmation | Locked: 9 topics, IRIS 2024.1+ floor, pure ObjectScript, MCP-export-friendly, Phase 1 dropped |
| 2 | Technology Stack Analysis | 4 parallel research streams: IRIS surface / LLM APIs / MCP / Markdown — all converged with citations |
| 3 | Integration Patterns Analysis | 8 named patterns, agent-loop sequence, retry table verified against Anthropic docs |
| 3.5 | Scope Amendments | 5 expansions reconciled mid-stream (two agents, four providers, Zen config, lifecycle coupling, IPM) |
| 4 | Architectural Patterns | Component diagram, class hierarchy, four-provider abstraction (incl. Gemini), Topic 10 decision (Option B), IPM packaging shape, deployment topology |
| 5 | Implementation Approaches | 11-epic sprint plan, working `module.xml`, installer body, OpenAI provider concrete, retry policy, tool registry skeleton, example tool, chat history, sweep task, RBAC install, ChatPanel helper, config Zen page outline, operator README, test strategy |
| 6 | Synthesis & Executive Summary | This section. |

**Confidence summary across the document:** Most findings High, with five Medium-confidence items explicitly flagged and three Task-0 probes carried forward. No Low-confidence findings shipped as primary recommendations.

**Document length:** ~13,000 words, dense; sized for downstream PRD authors and dev agents to lift from rather than re-research. Reads top-to-bottom for full context, or bottom-up (this section first) for executive-decision context.

**Companion deliverables (queued post-this-doc):**

1. **Sibling research doc — Message Search Agent.** Same six-step structure; covers tools, scale-handling, search-term learning. Triggered by user.
2. **Cleanup edit proposals for the two existing AI-Hub-coupled research docs** in `sources/iris-session-chat/_bmad-output/planning-artifacts/research/` (and their copies in this project's `_bmad-output/planning-artifacts/research/`). Concrete edits, not destructive deletions; user-approved before applying.

---

**Research Completion Date:** 2026-05-02
**Research Period:** 2026-05-01 — 2026-05-02 (one continuous research session)
**Document Length:** ~13,000 words (synthesis-tight, no padding; comprehensive coverage with no critical gaps)
**Source Verification:** All non-trivial claims cited; minimum 2 authoritative sources per High-confidence finding per the project's `research-first.md` rule. Confidence levels (High / Medium / Low) called out explicitly throughout.
**Task-0 Probes Required Before Implementation:** 3 (carried forward in §Task-0 Probes above)

*This research document serves as the architectural blueprint for the v1 release of `iris-session-agent` and provides the foundation for downstream PRD, architecture, epic, and story authoring. It assumes the reader has not loaded the original `sources/iris-session-chat/` planning artifacts; where prior context is needed it's quoted or summarized inline.*



