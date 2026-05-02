# Cleanup Edit Proposal — AI-Hub-Coupled Research Docs

**Date:** 2026-05-02
**Status:** Awaiting user approval — no edits applied yet
**Authoritative replacement doc:** [`technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md`](./technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md)
**Edit posture:** non-destructive (banners + inline blockquote callouts only); no content deletion.

---

The two 2026-04-24 docs were written when the project was AI-Hub-coupled (EAP build `2026.2.0AI.141.0`). The new authoritative research moves the project to **pure ObjectScript on IRIS 2024.1+**, two agents (Inspection + Search), four LLM providers via direct `%Net.HttpRequest`, and an MCP-exportable tool registry that replaces `%AI.ToolSet`/`%AI.Tool`/`<Query>`. The data-side schema work (`Ens.MessageHeader` correlation, body dispatch, the 14-column trace projection, Management-Portal subclassing, package mapping, hyperevent plumbing) **remains correct and load-bearing** — only the AI-Hub bindings are superseded.

---

## Document 1: `technical-ensemble-session-inspection-agent-research-2026-04-24.md` (2,851 lines)

### Proposed top-of-file banner

Insert immediately after the YAML frontmatter (before `# Research Report: Technical` on line 28):

```markdown
> **STATUS — PARTIALLY SUPERSEDED (2026-05-01)**
>
> This document was written against the InterSystems AI Hub EAP (build
> `2026.2.0AI.141.0`) and assumes `%AI.*` primitives (`%AI.Agent`,
> `%AI.ToolSet`, `%AI.Tool`, `%AI.Policy.Authorization`, `%AI.MCP.Service`,
> the `<Query>` element auto-schema, IRIS Wallet, etc.).
>
> The project pivoted on 2026-05-01 to a **pure-ObjectScript design on
> IRIS 2024.1+** — no AI Hub primitives, no embedded Python in the runtime
> path, MCP serving deferred (registry must stay MCP-exportable). The new
> authoritative research is:
>
> [`technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md`](./technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md)
>
> **What is still correct here** (preserved as-is): the entire data side —
> `Ens.MessageHeader`/`Ens.Util.Log`/`Ens.Rule.Log` schema, the SessionId
> correlation spine, body-class dispatch chain (9-step), the canonical
> 14-column trace projection from `EnsPortal.SVG.VisualTrace`, SQL
> idioms (`%EXACT`, `%ID`, `%ODBCOUT(ErrorStatus)`, `%EXTERNAL`,
> `CorrespondingMessageId` joins), the 13-tool catalog content,
> `%Dictionary.*` reflection, Health-specific trace cruft filters,
> `Ens.SuperSessionIndex` cross-instance linkage.
>
> **What is superseded**: every binding to `%AI.*`, `<Query>` auto-schema,
> the EAP IRIS build assumption, the Anthropic-only provider assumption,
> and IRIS Wallet (which does not exist in 2024.1 — see new doc §"Topic 8
> preflight"). Replacements: `%Net.HttpRequest` agent loop;
> `SessionAgent.Tool.Base`/`SessionAgent.Tool.Registry`; four-provider abstraction with
> OpenAI as ship-first concrete; three-layer read-only enforcement
> without `%AI.Policy.Authorization`; env-var → `Ens.Config.Credentials`
> for secrets.
>
> Inline section callouts below mark which pieces of each section are
> superseded vs. preserved. Read this doc for design rationale and
> data-side detail; read the 2026-05-01 doc for the v1 architecture and
> implementation path.
```

### Proposed section-level callouts

| Section header | Lines (approx) | AI-Hub coupling | Proposed callout text |
|---|---|---|---|
| `### The AI Hub SDK — Foundational Layer for the Agent Tool` | 179–202 | **High** | `> **⚠️ SUPERSEDED (2026-05-01):** The AI Hub SDK is no longer the foundation. The new design targets IRIS 2024.1+ where %AI.* does not exist; it builds the agent loop directly on %Net.HttpRequest + %DynamicObject against Anthropic Messages, OpenAI Chat Completions, Gemini generateContent, and Ollama/vLLM endpoints. See new doc §"Technology Stack Analysis" and §"LLM Provider Abstraction Pattern". The class-name inventory below (%AI.Agent, %AI.ToolSet, %AI.Skill, %AI.Provider) is preserved here as historical context for a future MCP-export epic, not as an implementation target.` |
| `### Source Reliability Assessment` (rows referencing `irislib/%AI/*` and `sources/ai-hub-eap/*`) | 213–224 | Medium | `> **⚠️ SUPERSEDED (2026-05-01):** The AI Hub source rows in this table are no longer authoritative for the v1 build (project moved off %AI.*). The Ens.* source rows remain authoritative.` |
| `### Known Gaps / To Verify in Later Steps` (items 1–3) | 226–231 | Medium | `> **⚠️ SUPERSEDED:** All three "verify in later steps" items targeted %AI.* and are obsolete. The new doc replaces them with three Task-0 probes against IRIS 2024.1: %Dictionary.* reflection, SELECT INTO :exists / SQLCODE=100, and the Web Gateway "Server Response Timeout".` |
| `## Technical Overview — Deep Dive (Extension)` (entire section) | 234–755 | **None** — preserve | *No callout. This section is entirely Ens schema, decode tables, body-class dispatch chain, runtime BP state, %Dictionary.* patterns. Reused verbatim by the new design.* |
| `## Integration Patterns — The Session Correlation Model` (subsections 1–13) | 757–1262 | **None** — preserve | *No callout. SessionId join graph, request/response correlation algorithms (Inproc + Queue), timeline reconstruction, body-class dispatch (9-step), VDoc handling, SearchTable patterns, SuperSession & MsgBank, Health-specific trace cruft filters, error correlation surfaces, namespace projection, data-format contract — all preserved. The new doc explicitly cites these as shared infrastructure.* |
| `### 14. Read-Only Enforcement Pattern` | 1263–1271 | Low | `> **🔄 PARTIALLY SUPERSEDED (2026-05-01):** The three-layer principle (method discipline + policy gate + RBAC) carries over. The middle layer is now a SessionAgent.Tool.Registry.Dispatch policy gate reading the tool's MutatesState parameter, not %AI.Policy.Authorization. See new doc §"Three-Layer Read-Only Enforcement Pattern".` |
| `### 15. Cross-Pattern Summary — The Integration Checklist` | 1272–1294 | None — preserve | *No callout.* |
| `## Architectural Patterns — AI Hub Agent & Tool Design` (entire `## ` section through subsection 13) | 1296–1665 | **High (entire section)** | Section-opening callout: `> **⚠️ SUPERSEDED (2026-05-01) — entire section.** This section's architecture is built on %AI.Agent, %AI.ToolSet, %AI.Tool, %AI.Policy.*, %AI.MCP.Service, the <Query> auto-schema XData element, IRIS Wallet via @{wallet.*} placeholders, and the EAP iris-mcp-server Rust binary. None of these exist on the IRIS 2024.1+ floor the project now targets. The new authoritative architecture is in the 2026-05-01 doc §"Architectural Patterns and Design": it replaces this section's components 1:1 with SessionAgent.Agent.AgentLoop, SessionAgent.LLM.Provider (4 concretes incl. Gemini), SessionAgent.Tool.Base + SessionAgent.Tool.Registry, three-layer read-only without %AI.Policy, env-var/Ens.Config.Credentials for secrets, and an MCP-exportable dispatch contract that defers MCP serving from v1. **The 13-tool catalog (subsection 4, lines 1423–1450) is preserved by reference — the same tools ship in v1, just bound to SessionAgent.Tool.Inspection.* instead of %AI.Tool subclasses.**` |
| `### 4. Tool Catalog — Proposed Schema` (the 13-tool table specifically) | 1423–1450 | Low (data side) | `> **🔄 BINDING SUPERSEDED, CONTENT PRESERVED (2026-05-01):** The 13 tool names, inputs, outputs, and SQL semantics here are correct and carry forward into v1. What changes: each tool becomes a SessionAgent.Tool.Base subclass under SessionAgent.Tool.Inspection.* with a SessionAgent.Tool.Registry-built JSON Schema, instead of a <Query> element inside an %AI.ToolSet XData block. The "Method 5b (<Query>)" column is no longer applicable.` |
| `### 7. Secret Management — Config Store + Wallet` | 1538–1553 | **High** | `> **⚠️ SUPERSEDED (2026-05-01):** **IRIS Wallet (%Library.IRISWallet) does not exist in IRIS 2024.1.** It was introduced in IRIS 2026.1. The @{wallet.*} placeholder syntax and the ^%AI.Config global are AI-Hub-specific and unavailable. The new doc's §"Pre-flight Findings" preflight verified this and substitutes a 2024.1-compatible secrets path: primary = $SYSTEM.Util.GetEnviron("ANTHROPIC_API_KEY") (container/Kubernetes-friendly); secondary = Ens.Config.Credentials (encrypted at rest in %SYS.Ensemble); last-resort = custom %Persistent + $System.Encryption.AESGCMEncrypt. Per-agent config rows hold a *reference* to the credential record, never the key itself.` |
| `### 8. Agent System Prompt — What to Tell the LLM` | 1554–1597 | None (content) — preserve | *No callout. The system prompt is provider-agnostic and reused.* |
| `### 9. Performance & Scalability Considerations` | 1599–1611 | Low | `> **🔄 PARTIALLY SUPERSEDED:** The "session size" mitigations remain valid. QUERYMAXROWS is no longer a parameter (no %AI.Tool parent); per-tool result-size caps are now enforced inside each SessionAgent.Tool.Inspection.* Invoke method. Add the new gateway-timeout concern from the 2026-05-01 doc: a synchronous-blocking turn must fit inside the Web Gateway "Server Response Timeout" (commonly 60s, recommended raised to 300s — operator README prerequisite).` |
| `### 10. Session Lifecycle (AI Session, not Ens Session)` | 1612–1623 | **High** | `> **⚠️ SUPERSEDED (2026-05-01):** %AI.Agent.Session does not exist on IRIS 2024.1. The new design uses a SessionAgent.Chat.History %Persistent class keyed on (agentName, sessionKey, portalUser), with chat-history lifecycle coupled to Ens.MessageHeader.Purge() (Topic 10 in new doc §"Architectural Patterns and Design", Option B chosen). Token-usage GetStats() is replaced by a custom audit ledger: SessionAgent.Audit.LlmCall (1 row/HTTP round-trip) + SessionAgent.Audit.ToolCall (1 row/dispatch), foreign-keyed to the chat history row.` |
| `### 11. Error Handling Pattern` | 1624–1633 | Low | `> **🔄 PARTIALLY SUPERSEDED:** Structured-error-object discipline carries over. Replace %AI.Errors.inc macros ($$$AICoreToolArg*) with a per-tool {isError: true, content: [...]} shape — the MCP tools/call envelope per the 2026-05-01 doc §"The Tool Dispatch Contract — MCP-Exportable Surface".` |
| `### 12. Source-Reliability Assessment for This Step` | 1634–1644 | Medium | *No callout.* (Self-explanatory caveat about EAP churn.) |
| `### 13. Gaps Closed in Step 4 → Step 5` | 1645–1664 | Medium | `> **⚠️ SUPERSEDED:** Every "closed" item references %AI.*. The new doc closes the equivalent gaps for the pure-ObjectScript path.` |
| `## Implementation Research — Concrete Code Patterns` (entire `## ` section) | 1667–2603 | Mixed — preserve data, supersede bindings | Section-opening callout: `> **🔄 IMPLEMENTATION SUPERSEDED, SCHEMA + SQL PRESERVED (2026-05-01):** The class skeletons in this section are AI-Hub-bound: Custom.EnsSession.Tools Extends %AI.ToolSet, <Query> XData elements with ROWSPEC=, Custom.EnsSession.Agent Extends %AI.Agent with Parameter TOOLSETS, %AI.Policy.Authorization subclass, @{wallet.*} API-key placeholder. None of these compile on IRIS 2024.1. **What is preserved by reference**: subsection 1's canonical EnsPortal.SVG.VisualTrace.cls SQL (the 14-column projection, ORDER BY %ID, the UNION ALL over Ens.Util.Log + Ens.Rule.Log, the SessionId-from-MessageId trick), the body-class dispatch logic (subsection 4's RenderHL7Body and the 9-step variant detection), the BP introspection method bodies (subsection 5), the error-decoder logic (subsection 6), and the system prompt content (subsection 9). All of this carries directly into the new SessionAgent.Tool.Inspection.* classes; only the class-extends and the <Query> declarative wrapper change.` |
| `### 1. The Canonical Session-Trace Query (from IRIS Management Portal)` | 1671–1718 | None — preserve | *No callout. Authoritative SQL reference.* |
| `### 2. Full Custom.EnsSession.Tools ToolSet Class Skeleton` | 1720–1751 | **High** | `> **⚠️ SUPERSEDED:** %AI.ToolSet does not exist on 2024.1; the <ToolSet> XML and <Policies> blocks are obsolete. New equivalent: SessionAgent.Tool.Registry.RegisterAgent("inspection", listOfToolClasses) enumerates SessionAgent.Tool.Base subclasses; the dispatch policy lives in SessionAgent.Tool.Registry.Dispatch.` |
| `### 3. Custom.EnsSession.Tools.Trace — The Timeline & Message Tools` | 1753–1978 | High (binding) / None (SQL) | `> **🔄 BINDING SUPERSEDED, SQL PRESERVED:** Each Query Name(...) As %SQLQuery(ROWSPEC=...) [SqlProc] becomes a SessionAgent.Tool.Base subclass whose Invoke() runs the same SQL via %SQL.Statement.%Prepare() and shapes a %DynamicObject result. The XData INSTRUCTIONS block above the queries carries over verbatim as the agent's system prompt.` |
| `### 4. Custom.EnsSession.Tools.Body — Body Retrieval Tool (Method 1+2)` | 1980–2109 | High (binding) / None (logic) | `> **🔄 BINDING SUPERSEDED, METHOD BODIES PRESERVED:** The GetMessageBody body-class dispatch ladder (%JSON.Adaptor → VDoc → %Stream.Object → %ZEN.Auxiliary.altJSONProvider generic fallback) and the HL7-specific RenderHL7Body are reused as-is inside SessionAgent.Tool.Inspection.GetMessageBody.Invoke().` |
| `### 5. Custom.EnsSession.Tools.Process — Business Process Inspection` | 2111–2289 | High (binding) / None (logic) | `> **🔄 BINDING SUPERSEDED, METHOD BODIES PRESERVED:** Class introspection logic via %Dictionary.ClassDefinition/MethodDefinition/XDataDefinition is unchanged.` |
| `### 6. Custom.EnsSession.Tools.Errors — Error Decoding` | 2290–2367 | High (binding) / None (logic) | `> **🔄 BINDING SUPERSEDED, METHOD BODIES PRESERVED.**` |
| `### 7. Custom.EnsSession.Tools.Meta — Meta and Search Tools` | 2368–2402 | High (binding) / None (logic) | `> **🔄 BINDING SUPERSEDED, METHOD BODIES PRESERVED.**` |
| `### 8. The Read-Only Policy` | 2403–2421 | **High** | `> **⚠️ SUPERSEDED:** %AI.Policy.Authorization does not exist on 2024.1. Replaced by SessionAgent.Tool.Registry.Dispatch reading each tool's ..#MutatesState parameter and short-circuiting with {isError: true, content: [{type: "text", text: "Tool blocked by read-only policy"}]} when the agent is configured read_only=true. See new doc §"Three-Layer Read-Only Enforcement Pattern" Layer 2.` |
| `### 9. The Agent Class` | 2423–2517 | **High** | `> **⚠️ SUPERSEDED:** %AI.Agent parent class, Parameter PROVIDER/MODEL/PROVIDERCONFIG/TOOLSETS, XData INSTRUCTIONS, agent.CreateSession(config), agent.Chat(session, ...) are all AI-Hub APIs absent on 2024.1. The new SessionAgent.Agent.AgentLoop.RunTurn() replaces them entirely. **The XData INSTRUCTIONS markdown content (the system prompt) carries over verbatim** — copy it into the SessionAgent.Config.Agent row's system-prompt column at install time.` |
| `### 10. VDoc Rendering Strategy (Detailed)` | 2519–2531 | None — preserve | *No callout.* |
| `### 11. LLM Context-Budget Considerations` | 2533–2553 | Low | `> **🔄 PARTIALLY SUPERSEDED:** The token-budget tables remain useful. session.GetStats() is replaced by SessionAgent.Audit.LlmCall row aggregation (per-provider audit; see new doc §"Audit Logging Cross-Cut Pattern" — log all four Anthropic usage fields, four OpenAI fields, four Gemini fields).` |
| `### 12. Testing Strategy` | 2554–2568 | None — preserve | *No callout.* |
| `### 13. Deployment Checklist` | 2569–2578 | **High** | `> **⚠️ SUPERSEDED:** Steps 1 (install AI Hub EAP), 2 (Wallet entry), 5 (MCP Server) are obsolete. Replacement deployment is via IPM (module.xml per new doc §"Implementation Approaches"), env-var or Ens.Config.Credentials for keys, and Web Gateway timeout raised to 300s as an operator prerequisite. MCP serving is deferred from v1.` |
| `### 14. Known Limitations & Future Extensions` | 2579–2590 | None — preserve | *No callout.* |
| `### 15. Source Reliability Assessment for This Step` | 2591–2602 | Low | *No callout.* |
| `# Research Synthesis & Executive Summary` (entire `# `-prefixed section through end) | 2606–2845 | **High (top-level claims)** | Section-opening callout: `> **⚠️ SUPERSEDED (2026-05-01) — entire executive summary.** Top-line conclusions ("AI Hub SDK provides every primitive we need", the "13 tools" recommendation, Wallet-based secrets, "EAP API churn is a real risk") are obsolete. The Strategic Recommendations R1–R7 are all AI-Hub-bound. The 4-phase Implementation Roadmap targets the wrong build. Use the 2026-05-01 doc §"Research Synthesis & Executive Summary" as the current authoritative summary. **Preserved from this section by reference**: the data-correlation findings (SessionId equality, request/response correlation via CorrespondingMessageId, IsError-on-response gotcha, dynamic body typing, deprecated Ens.Rule.RuleLog, Management-Portal canonical query shape) — all reused unchanged. The PHI/sensitive-body-data risk note (lines 2785–2796) carries forward and is restated in the new doc.` |

### Sections preserved as-is (no edit)

- **§"Technical Overview — Foundational Landscape"** (lines 82–177, except `### The AI Hub SDK` at 179) — Production model, message-header/body separation, SessionId correlation spine, five core tables, message lifecycle, message-type decoders. Authoritative for v1.
- **§"Technical Overview — Deep Dive (Extension)"** (lines 234–755) — Decode tables, body-class resolution, event log Type decoder, rule log, queue runtime, BP persistent state, Activity tables, Runtime Job-Local State, programmatic class introspection.
- **§"Integration Patterns — The Session Correlation Model"** (lines 757–1262 except subsection 14) — All 13 patterns.

---

## Document 2: `technical-ensemble-session-agent-ui-integration-research-2026-04-24.md` (1,241 lines)

### Proposed top-of-file banner

Insert immediately after the YAML frontmatter (before `# Research Report: UI Integration Architecture` on line 32):

```markdown
> **STATUS — PARTIALLY SUPERSEDED (2026-05-01)**
>
> This document was written against the InterSystems AI Hub EAP and
> assumes %AI.Shell.Console (Phase 1 terminal REPL),
> %AI.Agent.Session (CSP-cross-request state persistence),
> Custom.EnsSession.Agent extends %AI.Agent, IRIS Wallet
> (@{wallet.AISecrets.AnthropicKey}), %AI.System.RenderMarkdown,
> and %AI.Utils.SettingStore. The dependent doc
> (technical-ensemble-session-inspection-agent-research-2026-04-24.md)
> has been similarly superseded.
>
> The project pivoted on 2026-05-01 to a **pure-ObjectScript design on
> IRIS 2024.1+** with two agents (Inspection + Search), four LLM
> providers, a custom SessionAgent.Agent.AgentLoop, a SessionAgent.Chat.History
> %Persistent class for cross-request state, and a vendored
> client-side marked + Prism + DOMPurify markdown bundle. The
> authoritative replacement is:
>
> [`technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md`](./technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md)
>
> **What is still correct here** (preserved as-is): the entire
> EnsPortal subclassing analysis — the EnsPortal.VisualTrace /
> EnsPortal.MessageViewer parent chains, the
> Ens.Enterprise.Portal.VisualTrace prior-art proof that subclassing
> works, the XData allTabs 4th-tab pattern, ZenMethod hyperevent
> plumbing, OnDrawContent callbacks, GetHyperEventResources
> override, HSCUSTOM + package-mapping deployment topology,
> %session.Data cross-request state mechanics, namespace-switching
> safety in CSP context, keepAlive portal mechanism, the Phase 3
> one-line showTrace() handoff, and the bookmark URL pattern.
>
> **What is superseded**: Phase 1 (terminal REPL via %AI.Shell.Console)
> is dropped from v1 entirely. The Phase 2
> Custom.EnsSession.Agent extends %AI.Agent and %AI.Agent.Session
> persistence pattern are replaced by a custom SessionAgent.Agent.AgentLoop
> + SessionAgent.Chat.History keyed on (agentName, sessionKey, portalUser).
> Wallet-based API keys → env-var or Ens.Config.Credentials. The
> MarkdownToHtml server-side stub is replaced by client-side
> rendering (vendored marked + Prism + DOMPurify). The new doc adds
> a sibling **SessionAgent.EnsPortal.MessageViewer chat tab** for the
> Message Search Agent.
```

### Proposed section-level callouts

(Same shape as Document 1 — see the Agent's full output above. ~13 callouts marking Phase 1 sections, %AI.Agent.Session sections, agent class binding sections, server-side markdown rendering, etc. The complete table is in the agent's full proposal output.)

### Sections preserved as-is (no edit)

- **§1.2** — `Ens.Enterprise.Portal.VisualTrace` subclassing prior-art proof.
- **§3** — ZenMethod AJAX plumbing (pure Zen framework).
- **§4** — CSP deployment topology + package mapping + bookmark URL pattern.
- **§5** — Namespace switching safety in CSP.
- **§6.4** — Context-aware chat (selectedMessageId enrichment).

---

## Order of operations (recommended)

1. **User reviews this proposal** — approves or requests changes per-section.
2. **Apply edits to project copies** in `c:/git/iris-session-agent/_bmad-output/planning-artifacts/research/` first, in this order:
   1. Inspection-agent doc — top-of-file banner
   2. Inspection-agent doc — inline blockquote callouts
   3. UI-integration doc — top-of-file banner
   4. UI-integration doc — inline blockquote callouts
3. **Verify rendering** — view both edited docs in markdown to confirm callouts read clearly.
4. **Mirror to the `sources/iris-session-chat/` copies** — apply identical edits to the two copies in `sources/iris-session-chat/_bmad-output/planning-artifacts/research/`.
5. **Commit** as a single non-destructive cleanup commit on `main` ("annotate AI-Hub-coupled research as partially superseded by 2026-05-01 doc").
6. **Optional follow-up** — add a one-paragraph cross-reference in the new 2026-05-01 doc's "Out of scope" section pointing back to these two annotated docs as historical design rationale.

---

**Total proposed edits:** 2 banners + ~35 inline blockquote callouts across both docs. **Zero deletions.** All historical content preserved for design-rationale and future-MCP-epic reference.
