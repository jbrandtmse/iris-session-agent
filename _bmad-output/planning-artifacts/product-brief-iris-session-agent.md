---
title: "Product Brief: iris-session-agent"
version: "1.0"
date: "2026-05-02"
author: "Joshua Brandt"
license: "MIT"
status: "Draft — pending PRD authoring"
---

# Product Brief: iris-session-agent

> *"Chatting with your Interoperability Session to really understand what happened — and finding the right session by asking."*

## Executive Summary

`iris-session-agent` is an open-source IRIS module that adds an AI assistant chat experience to the InterSystems Management Portal for Interoperability operators. Two agents — a **Session Inspection Agent** that explains what happened in a given Ensemble session, and a **Message Search Agent** that helps operators find sessions by natural-language query — share infrastructure inside one IPM-installable package and run on **IRIS / IRIS for Health 2024.1+** in pure ObjectScript with no embedded Python and no AI Hub dependency.

The product fills a structural gap: an Ensemble session leaves a trace across six separate data surfaces (`Ens.MessageHeader`, message bodies, `Ens.SearchTableBase` indexes, `Ens.Util.Log`, `Ens.Rule.Log`, BP runtime state), and operators today join those surfaces in their heads — every time, on every incident, starting from scratch. Junior engineers can't do this at all without senior help. `iris-session-agent` collapses 20-30 minutes of expert tab-switching into a 30-second conversation, and gives junior engineers the ability to do senior-level diagnosis. It originated as a planned hackathon project at InterSystems READY 2026 and is now an independent, single-author hobby project published as open source from day one.

## The Problem

A production Ensemble session that completes successfully takes seconds. A session that fails — or worse, partially fails in a way that produces silent data loss — takes 20-30 minutes for a senior engineer to diagnose, and is roughly impossible for a junior engineer to diagnose alone. The reason isn't that the data isn't there. It's that the data is *scattered*:

- The **message headers** (`Ens.MessageHeader`) tell you the call graph, the configuration hosts involved, the status, the timing, and where errors flagged.
- The **message bodies** are dynamically-typed `%Persistent` instances of arbitrary classes — HL7 messages, FHIR resources, X12 transactions, custom request/response objects — and you have to know the class to render them sensibly.
- The **search-table indexes** (`Ens.SearchTableBase` subclasses such as `EnsLib.HL7.SearchTable`) are a parallel indexed extent joined on `MessageBodyId` that exposes curated body fields — patient ID, MRN, order # — so operators can find sessions by body content without opening every body.
- The **event log** (`Ens.Util.Log`) carries the operational narrative — adapter retries, queue events, custom `$$$LOG*` calls.
- The **rule log** (`Ens.Rule.Log`) explains why the routing rule engine sent each message where it did.
- The **business process runtime state** (`Ens.BP.Context`, `Ens.BP.Thread`) reveals what the BP was thinking at each await/sleep boundary — if it's a BPL process or a custom subclass.

Every diagnostic conversation today goes: *open Visual Trace, mentally cross-reference with Message Viewer, alt-tab to Event Log, scroll Rule Log, switch namespace, open the BP class source, read it, switch back, repeat.* On-call engineers do this at 2am.

The cost: senior-engineer time at premium hours, junior engineers blocked, on-call burnout, and missed correlated errors that span the surfaces nobody opened.

## The Solution

A chat panel embedded in the IRIS Management Portal — one tab inside the existing Visual Trace page, one tab inside the existing Message Viewer page. The operator opens the Visual Trace on a session and asks "what happened?" The agent reads the headers, opens the bodies, correlates with the event log and rule log, looks at the BP source if needed, and answers in plain English. If the operator doesn't know which session they're looking for yet, they open the Message Viewer's chat tab and ask "find me sessions where X" — the agent runs natural-language queries over `Ens.MessageHeader` (and SearchTable-indexed body fields, and unindexed body content via a two-stage narrow-then-inspect pattern), surfaces a curated short list, and clicks through to the inspection agent on whichever session the operator picks.

The chat is **read-only** by design — three layers of enforcement (code discipline, dispatch policy gate, IRIS RBAC SELECT-only role) make it operationally impossible for the agent to mutate production data. Configuration is per-agent through a Zen UI: pick the LLM provider (OpenAI, Anthropic, Google Gemini, or self-hosted Ollama), pick the model, point at the API key (env-var or `Ens.Config.Credentials`), set the temperature. The Search Agent learns the operator's vocabulary and per-message-body-class search idioms over time, so the third time an operator asks for "failed admits" they get instantly-correct results.

## What Makes This Different

The IRIS Interoperability ecosystem has no purpose-built AI tool. General AIOps platforms (Datadog Bits, Dynatrace Davis, Splunk AI, IBM AIOps) are the obvious comparators, and they're all blind to Ensemble — IRIS produces no OpenTelemetry, the message-header schema is invisible to ingest pipelines, the routing-rule semantics don't translate. Boomi's Integration Advisor Agent works at design-time, not runtime. InterSystems' own AI Hub SDK enables an Anthropic-like agent loop natively in IRIS, but it's pre-release (EAP), and the IRIS installed base — particularly HealthShare deployments running 2024.1 — won't have it for some time.

The unfair advantage of `iris-session-agent` isn't a moat — it's *fit*. The agent is built by an IRIS engineer for IRIS engineers, on the IRIS the community already has, and it ships open source. The community can install it from Open Exchange today, run it in their own namespace, point it at their own LLM provider with their own API key, and get value before any vendor-AI roadmap delivers.

## Who This Serves

**Primary users**: InterSystems IRIS / Ensemble integration engineers and operators on IRIS / IRIS for Health 2024.1+ — the people who carry the on-call pager when an interface partner's HL7 feed starts failing or a BPL process gets stuck. Especially on-call engineers debugging incidents at 2am, and especially **junior engineers** who can do far more with the agent's help than they can alone.

**Secondary users**: integration leads and engineering managers who want to onboard new engineers faster, and the broader IRIS open-source community who'll evaluate, install, fork, and contribute through Open Exchange.

## Success Criteria

The brief is honest about what success looks like for a single-author hobby project published open source:

- **Operators' time-to-resolution measurably drops** when using the agent vs. tab-switching by hand. The original brief's benchmark — replace 20-30 minutes of expert work with a 30-second conversation — is the aspirational target; even a "5 minutes → 1 minute" win on common diagnoses is meaningful.
- **At least one customer site adopts it for production diagnosis.** Real adoption — operators integrate it into their on-call workflow — is the metric that matters. One genuinely-using customer beats a hundred curious downloads.

Vanity metrics (download counts, stars, maintenance-longevity for its own sake) are **explicitly not** the success criteria. This is a hobby project; the author's satisfaction comes from operators getting their evenings back.

## Scope

**In for v1** (full scope, delivered incrementally):

- Two agents — Session Inspection Agent and Message Search Agent — both embedded as chat tabs in custom Management Portal subclasses.
- Four LLM providers — OpenAI (ships first), Anthropic, Google Gemini, Ollama / vLLM (any OpenAI-compatible self-hosted endpoint). Provider framework extensible.
- Per-agent Zen-page configuration with API keys held in env-vars or `Ens.Config.Credentials`, never in the config row.
- Per-user vocabulary learning for the Search Agent, scoped per message-body-class.
- Body-content search beyond indexed fields, via a two-stage narrow-then-inspect pattern.
- Read-only enforcement at three layers (code discipline, dispatch policy gate, IRIS RBAC role).
- Audit logging of every LLM round-trip and tool dispatch.
- IPM-installable as a single module (`zpm install iris-session-agent`).
- Chat-history lifecycle coupled to `Ens.MessageHeader.Purge()` for the inspection agent; TTL-based for the search agent.

**Out for v1** (intentional deferrals):

- MCP serving — handled by the sibling [`iris-execute-mcp-v2`](https://github.com/jbrandtmse/) project, not this one. The tool registry stays MCP-exportable so that suite can wrap it.
- Phase 1 terminal REPL — the original brief's stand-alone CLI bot is dropped from v1.
- Vector / semantic search on message bodies — body-content search is keyword/regex/LLM-evaluation-bounded-by-indexed-prefilter; semantic search is a v2 concern.
- Cross-namespace single-conversation operation — each bookmark targets one namespace.
- PHI redaction architecture — the namespace-scoped PHI segregation already practiced by IRIS customers is the v1 boundary; a redaction layer is post-v1.
- Embedded Python in the runtime path — pure ObjectScript only.
- Vendor commercial licensing or SI-partner channel — open source, day one.

**Delivery cadence**: full-scope plan, **incremental release**. Pre-alpha builds get into operators' hands as early as possible — the eleven-epic sprint sequence in the technical research doc has Epic 6 producing the first demo-able OpenAI-powered Inspection Agent, well before later epics add the second agent, additional providers, and polish. Milestones drive releases, not dates.

## Vision

If `iris-session-agent` succeeds: the IRIS / Ensemble community gains a baseline expectation that interoperability operators can chat with their productions. The pattern — pure-ObjectScript LLM agents, MCP-exportable tool registries, per-agent Zen-page configuration — becomes a reference implementation that other IRIS-domain agents are built on (a Production Health Agent watching `Ens.Util.Statistics`, a Schema Discovery Agent for FHIR transitions, a Migration Assistant for HealthShare upgrades). The product is small enough for one person to maintain, valuable enough that the community contributes, and open enough that anyone can fork it for their own domain.

In a 2-3 year horizon, when InterSystems' own AI Hub matures and goes GA, `iris-session-agent` may become a community-maintained alternative for the long tail of older-IRIS deployments, a teaching example for the pure-ObjectScript-agent pattern, or both. The work — and the engineers' evenings it gives back — stand on their own regardless.

---

## Origin

`iris-session-agent` was scoped during the InterSystems READY 2026 internal hackathon as the *Ensemble Session Inspection Agent* (planned but not selected for the 4-hour build window). It is now an independent open-source hobby project; the hackathon mention is origin attribution only.

## License

**MIT** — inherited posture from [`sources/iris-session-chat/LICENSE`](sources/iris-session-chat/LICENSE). A `LICENSE` file lands at the repo root in the v1 release commit.

## Companion Documents

- [Pure-ObjectScript Session Inspection Agent — research doc](_bmad-output/planning-artifacts/research/technical-pure-objectscript-session-inspection-agent-no-ai-hub-research-2026-05-01.md) — full v1 architecture
- [Pure-ObjectScript Message Search Agent — research doc](_bmad-output/planning-artifacts/research/technical-pure-objectscript-message-search-agent-no-ai-hub-research-2026-05-02.md) — search-agent companion
- [Distillate](product-brief-iris-session-agent-distillate.md) — token-efficient detail capture for downstream PRD context
- [`docs/initial-prompt.md`](docs/initial-prompt.md) — author's authoritative scope spec
