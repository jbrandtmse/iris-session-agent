# Epic 5 Operator State Checklist

**Date prepared:** 2026-05-06
**Lead:** Claude Opus 4.7
**Purpose:** Per Rule 7 (operator setup at sprint planning), enumerate every operator-side prerequisite for Epic 5 stories so credentials/configs are wired BEFORE per-story dev cycles run live tests. This file is the binding pre-flight reference for `/epic-cycle epic 5`.

## Scope

Epic 5 ships **4 stories** adding multi-provider LLM support:
- **Story 5.1** — `SessionAgent.LLM.AnthropicProvider` (concrete provider)
- **Story 5.2** — `SessionAgent.LLM.GeminiProvider` (concrete provider)
- **Story 5.3** — `SessionAgent.LLM.OpenAICompatProvider` (concrete provider; targets Ollama / vLLM / LM Studio)
- **Story 5.4** — Tool-call round-trip integration test infrastructure across all providers

Per Rule 11 (live integration smoke test mandatory), each provider story needs a live API call against the actual external surface — not just mock-only verification. Per Story 4.6 dev's experience, OpenAI key presence was a per-story gate; Epic 5 multiplies that risk by 4.

## Operator Prerequisites — Status

### 1. Cloud-provider credentials (wired into `Ens.Config.Credentials`)

| Story | Credential ID | Username marker | State | Verified resolvable via `Util.EnvSecret.IsResolvable` |
|---|---|---|---|---|
| 2.x baseline | `SessionAgentOpenAI` | `openai-bearer` | ✓ wired (Story 2.9) | ✓ |
| 5.1 | `SessionAgentAnthropic` | `anthropic-bearer` | ✓ **wired 2026-05-06** | ✓ |
| 5.2 | `SessionAgentGemini` | `gemini-key` | ✓ **wired 2026-05-06** | ✓ |
| 5.3 | `SessionAgentOpenAICompat` | (n/a for default Ollama) | n/a — **no credential needed for Ollama** | n/a |

Anthropic + Gemini API keys came from the user 2026-05-06 and persist in `Ens.Config.Credentials`. Source-of-truth fallback: `.keys` file at repo root (gitignored — `.gitignore:41-42`). Never echoed in repo content; never committed.

### 2. OpenAI-compatible endpoint URL (Story 5.3)

| Setting | Value | State |
|---|---|---|
| Endpoint | `http://192.168.0.123:11434/v1` | network-hosted Ollama (per user 2026-05-06) |
| Default model | `qwen3:14b` | quantized 14B-param tool-use chat model |
| Auth | none (Ollama default) | Story 5.3 spec must SUPPORT optional Bearer auth for other OpenAI-compatible endpoints (LM Studio with auth, vLLM behind proxy, etc.) |

**Where the URL lives at runtime:** TBD by Story 5.3 spec — likely a new property on `SessionAgent.Config.Agent` (e.g., `ProviderEndpointUrl`) so per-agent configuration overrides the default. Story 5.3 dev decides; the default URL `http://192.168.0.123:11434/v1` is the network Ollama on the user's LAN.

### 3. Cost-effective model defaults (Rule 10 spec-time research, 2026-05-06)

Stories 5.1, 5.2, 5.3 each set a canonical default model. Per the Epic 2 retro Rule 10 codification, defaults must be Perplexity / official-pricing-page-verified at spec time.

| Provider | Default model id | Input $/MTok | Output $/MTok | Source | Rationale |
|---|---|---|---|---|---|
| Anthropic (Story 5.1) | `claude-haiku-4-5-20251001` | $1.00 | $5.00 | [`platform.claude.com/docs/en/about-claude/pricing`](https://platform.claude.com/docs/en/about-claude/pricing) (verified 2026-05-06) | Cheapest current Claude tier; pricing page explicitly recommends Haiku for "simple tasks" — inspection-tool dispatch is mechanical and Haiku-sized. Tool-use system prompt overhead 346 tokens (`auto`/`none`). Optional override: `claude-sonnet-4-6` ($3 / $15) for harder reasoning. |
| Google Gemini (Story 5.2) | `gemini-2.5-flash` | $0.30 | $2.50 | [`ai.google.dev/gemini-api/docs/pricing`](https://ai.google.dev/gemini-api/docs/pricing) (verified 2026-05-06) | Pricing page recommends Flash for "agentic tasks requiring reasoning"; Flash-Lite at $0.10/$0.40 is cheaper but less reliable on tool dispatch. Free tier available. Optional override: `gemini-2.5-pro` ($1.25-$2.50 / $10-$15) for harder reasoning. |
| OpenAI-compatible (Story 5.3) | `qwen3:14b` (Ollama) | local | local | per user 2026-05-06 | 14B-param quantized chat model with tool-use support; runs on the user's network-hosted Ollama. Operator-overridable via `Config.Agent` for any OpenAI-compatible model. |
| OpenAI (existing baseline) | `gpt-4.1-mini` | $0.40 | $1.60 | Story 2.4 (verified 2026-04-XX per Epic 2 retro) | Locked-in default since Story 2.4. |

**Avoid pricing-newer / preview tiers as defaults:** Gemini 3.x preview tier ($2.00-$4.00 / $12.00-$18.00) is more expensive and less stable; Anthropic Opus 4.7 ($5 / $25) is over-spec for tool dispatch. Per Rule 10 verification line each provider story will paste into Dev Notes:

> *Verified current as of 2026-05-06 via [provider pricing page URL]: <model id> at <input>/<output> $/MTok recommended as cost-effective default for tool-use agents per [pricing page recommendation phrase]. Optional override <higher-tier model> for harder reasoning.*

### 4. Sample production state

Verified RUNNING as of 2026-05-04 (Epic 4 closing battery + manual-test pass). 5+ sample-prod sessions available for Epic 5 live tests:

| Session | Status | Tool-test value |
|---|---|---|
| 1844 | completed (no errors) | happy-path multi-tool turn |
| 1851 | completed (no errors) | happy-path |
| 1858 | completed (1 message, validation_error scenario) | error-path single-message |
| 2114 | completed (with errors — businessOperationFailure) | event_log + explain_error real-error flow |
| 2121 | completed (no errors) | happy-path |

Per Story 5.0 carry-forward Item D (Rule 7 watch-item from Epic 4 retro), sample production should be re-Bootstrapped at Epic-cycle Step 1 if it's been uninstalled — the user's 2026-05-04 manual-test pass left it RUNNING, but if state has changed since, re-Bootstrap before Story 5.1 dev:

```objectscript
do ##class(SessionAgent.Sample.Bootstrap).Install()
do ##class(SessionAgent.Sample.Bootstrap).StartProductionIfStopped()
```

### 5. SSL/TLS configuration

`DefaultSSL` config still in place from Epic 1 / Story 1.4. Anthropic + Gemini both require HTTPS to their respective hosts:

| Provider | Outbound host | SSL config |
|---|---|---|
| OpenAI | `api.openai.com` | `DefaultSSL` (existing) |
| Anthropic | `api.anthropic.com` | `DefaultSSL` (reuse — same TLS profile) |
| Google Gemini | `generativelanguage.googleapis.com` | `DefaultSSL` (reuse) |
| Ollama (local) | `192.168.0.123:11434` (no TLS) | n/a — HTTP, no SSL config |

No new SSL config required for Epic 5; `DefaultSSL` covers all three cloud providers. Verify with `SELECT Name FROM Security.SSLConfigs WHERE Name = 'DefaultSSL'` from `%SYS`.

### 6. RBAC

`SessionAgent_ReadOnly` role still in place from Story 1.4. No Epic 5 RBAC changes required — the four providers all run inside the same agent runtime that already has the role.

### 7. Browser availability (Rule 12 visual gate prep)

chrome-devtools-mcp browser was available throughout Story 4.7 and the manual-test pass. Lock state should be checked at Story 5.x dev time per the established escalation pattern (Stories 4.0 + 4.1 hit the lock; Story 4.6 honored the don't-substitute rule). Epic 5 stories may not directly add UI changes (provider classes are backend), but the live OpenAI smoke turns + cross-provider round-trip tests benefit from visual capture.

## Pre-flight checklist (Story 5.0 Step 1 of `/epic-cycle epic 5`)

- [ ] Sample production state confirmed RUNNING (or re-Bootstrap)
- [ ] `SessionAgentAnthropic` resolvable via `Util.EnvSecret.IsResolvable("", "SessionAgentAnthropic")` returning 1
- [ ] `SessionAgentGemini` resolvable via `Util.EnvSecret.IsResolvable("", "SessionAgentGemini")` returning 1
- [ ] `SessionAgentOpenAI` still resolvable (sanity check — Story 4.7 confirmed it works)
- [ ] Ollama server at `http://192.168.0.123:11434/v1` reachable (one-liner test: `curl http://192.168.0.123:11434/v1/models`)
- [ ] `DefaultSSL` SSL config still present in `Security.SSLConfigs`
- [ ] `SessionAgent_ReadOnly` role still present in `Security.Roles`
- [ ] Sample production scenarios producing fresh sessions (`RunScenario("none")` returns a non-zero session id)
- [ ] chrome-devtools-mcp browser unlock state acceptable

## Story 5.0 carry-forward triage (provisional — locked at retro time)

Per the [Epic 4 retro must-fix table](epic-4-retro-2026-05-04.md), Story 5.0 will land:

- **Item A (Rule 6 sub-clause + `object-script-testing.md` sharpening):** SQL-probe-as-ground-truth for test-pass verification — codifies the Story 4.7 reviewer's catch via `^UnitTest.Result.TestMethod` direct probe vs trusting MCP envelope
- **Item B (Rule 2 sharpening):** verbatim AC-contract output required in Completion Notes, not just tests-passing
- **Item C (Rule 4 watch-item):** operator-facing static text vs shipped-capability divergence as a stale-reference scan target
- **Item D (Rule 7 watch-item):** Sample production re-Bootstrap at Epic-cycle Step 1, not per-story
- **Item E (`<Ens>ErrGeneral` + 4 codes):** `ExplainError.BuildErrorTable()` additions

Estimated Story 5.0 scope: ~30 lines of rule-file edits + ~10 lines of `ExplainError.BuildErrorTable` additions + 2-3 new tests. Comfortably under Rule 1 250-line cap.

## Sources cited at Rule 10 verification

- Anthropic pricing: [`https://platform.claude.com/docs/en/about-claude/pricing`](https://platform.claude.com/docs/en/about-claude/pricing) — verified via WebFetch 2026-05-06.
- Gemini pricing: [`https://ai.google.dev/gemini-api/docs/pricing`](https://ai.google.dev/gemini-api/docs/pricing) — verified via WebFetch 2026-05-06.
- OpenAI pricing: Story 2.4 historical research (last verified Epic 2 timeframe; re-verify if Story 5.4 round-trip test surfaces drift).
- Ollama: per user 2026-05-06 — `qwen3:14b` quantized chat model on `http://192.168.0.123:11434/v1`.

## Change log

| Date | Change | Author |
|---|---|---|
| 2026-05-06 | Initial Epic 5 operator-state checklist drafted; Anthropic + Gemini credentials wired and verified resolvable; Ollama URL + qwen3:14b model captured; Rule 10 model defaults research-verified | Claude Opus 4.7 (lead) |
