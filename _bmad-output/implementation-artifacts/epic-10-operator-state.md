# Epic 10 Operator State (built at /epic-cycle Step 1)

**Date:** 2026-05-07
**Lead:** Claude Opus 4.7 (1M context)
**Apply:** Rule 7 §"Operator setup at sprint planning" + new §"Credential-resolvability matrix at Step 1" (codified by Story 10.0 AI-2; applied today per Epic 9 retro critical-path-item).

## Credential-resolvability matrix

Built BEFORE per-story dispatch. Source of truth for which provider live tests can run during Epic 10's empirical battery (Story 10.9 PRD v1 validation walkthrough).

| Provider | EnvVar | Credential ID | `Util.EnvSecret.IsResolvable` | Live test default |
|---|---|---|---|---|
| OpenAI | `OPENAI_API_KEY` | `SessionAgentOpenAI` | **1** | available |
| Anthropic | `ANTHROPIC_API_KEY` | `SessionAgentAnthropic` | **1** | **available — primary NFR-P6 verification path** |
| Gemini | `GEMINI_API_KEY` | `SessionAgentGemini` | **1** | available |
| OpenAICompat (Ollama) | (local instance) | (n/a) | (local) | available if local Ollama up |

**Probe transcript (verbatim):**

```
mcp__iris-interop-mcp__iris_credential_list →
  {"credentials":[
    {"id":"SessionAgentAnthropic","username":"anthropic-bearer"},
    {"id":"SessionAgentGemini","username":"gemini-key"},
    {"id":"SessionAgentLiveProbeOpenAI","username":"openai-bearer"},
    {"id":"SessionAgentOpenAI","username":"openai-bearer"}
  ],"count":4}

SessionAgent.Util.EnvSecret.IsResolvable("OPENAI_API_KEY","SessionAgentOpenAI")        → 1
SessionAgent.Util.EnvSecret.IsResolvable("ANTHROPIC_API_KEY","SessionAgentAnthropic") → 1
SessionAgent.Util.EnvSecret.IsResolvable("GEMINI_API_KEY","SessionAgentGemini")       → 1
```

**Conclusion:** All three commercial providers are live-test-default-available for Story 10.9's PRD v1 validation walkthrough. No "skipped" live test in Epic 10 may cite resolvability=0 — credentials are present.

## Sample production state

Probed `Ens.Director.IsProductionRunning` at Step 1 — returned `0` (stopped). Started via `SessionAgent.Sample.Bootstrap.StartProductionIfStopped` → returned `1`. Re-probed `Ens.Director.IsProductionRunning` → `1`.

Sample production is running for Epic 10's per-story dispatch. Per Rule 7 §"Step-1-time only — NOT per-story", per-story devs do NOT need to re-probe; the Step 1 amortization holds.

## In-scope external APIs for Epic 10

| Story | External API touch | Live-test gate |
|---|---|---|
| 10.0 | None (rule + deferred-work codification only) | n/a |
| 10.1–10.5 | None (UI / Zen surface; consumes already-shipped backend) | n/a |
| 10.6 | None (sweep tasks against IRIS-side `%Persistent` rows) | n/a |
| 10.7 | None (vendored Markdown bundle + asset shipping) | n/a |
| 10.8 | None (UI growth-tier components) | n/a |
| **10.9** | **Anthropic + OpenAI + Gemini live-test gates for PRD v1 validation** | **available — all three resolvable** |
