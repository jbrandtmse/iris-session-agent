# Epic 14 Operator State — Trace Intelligence

**Captured:** 2026-06-10 (UTC 2026-06-11T05:49Z) at /epic-cycle Step 1 (Rule 7 gate).
**Namespace:** HSCUSTOM (`local` server, localhost:52773).

## Sample-production state (Rule 7 watch-item, Step-1-time check)

| Probe | Result |
|---|---|
| `Ens.Director.IsProductionRunning` | **1** (running) — verified via `iris_execute_classmethod` |
| `Ens.MessageHeader` count / sessions | 50 headers / 8 sessions, latest `2026-06-11 05:49:43` |
| Scenario top-up | `SessionAgent.Sample.BS.OrderIngest.RunScenario` run 3× at Step 1 (fresh-server deploy had only 29 headers) |

Note for the Rule 6 epic-end battery: run additional `RunScenario` passes before the
golden-question walkthrough if richer volume/latency distributions are needed
(Epic 14 eval questions include failure-rate-by-dimension and volume-trend shapes).

## Credential-resolvability matrix (Rule 7 / Epic 9 retro AI-2)

Probed via `SessionAgent.Util.EnvSecret.IsResolvable(envVar, credentialName)`:

| Row | Provider | EnvVar | CredentialName | Resolvable? | First-story-needing |
|---|---|---|---|---|---|
| 1 | openai (both agents' configured provider, model `gpt-4.1-mini`) | `OPENAI_API_KEY` | `SessionAgentOpenAI` | **1** | 14.5 (golden-question eval pass) + Rule 6 battery |
| 2 | anthropic | `SESSIONAGENT_ANTHROPIC_API_KEY` | `SessionAgentAnthropic` | **1** | Rule 6 battery (multi-provider chat-panel pass if scoped) |
| 3 | gemini | `SESSIONAGENT_GEMINI_API_KEY` | `SessionAgentGemini` | **1** | Rule 6 battery (multi-provider chat-panel pass if scoped) |
| 4 | openai-compatible | resolves via `OPENAI_API_KEY` / `SessionAgentOpenAI` (no dedicated credential row; Story 11.4 precedent) | — | **1** (via row 1) | Rule 6 battery |

All in-scope live tests are DEFAULT AVAILABLE (no `Resolvable? = 0` rows). No live-test
deferral is authorized by this matrix.

## Config.Agent rows (operator storage, probed at Step 1)

| AgentName | Provider | Model | EnvVarName | CredentialName | Enabled |
|---|---|---|---|---|---|
| session-inspection | openai | gpt-4.1-mini | OPENAI_API_KEY | SessionAgentOpenAI | 1 |
| message-search | openai | gpt-4.1-mini | OPENAI_API_KEY | SessionAgentOpenAI | 1 |

## Epic 14 prerequisites checklist

| Prerequisite | Story | State |
|---|---|---|
| `docs/iris-query-guide/` (10 files, commit `89c5fce`) — knowledge corpus source | 14.1 | ✅ present (10 files verified) |
| `sprint-change-proposal-2026-06-10.md` — source-of-truth design artifact | all | ✅ present |
| LLM provider credential (eval pass + battery) | 14.5 | ✅ matrix rows 1–4 |
| Sample production running with scenario data | 14.0, 14.3, 14.5 | ✅ running, 8 sessions |
| No new external APIs, SSL configs, env-vars, or RBAC grants introduced by Epic 14 stories | — | confirmed from epic scope (all new surfaces are in-namespace SQL/persistence/prompt work) |

No operator-supplied gaps → no user-batched credential request required at Step 1.
