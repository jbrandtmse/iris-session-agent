# iris-session-agent — Operator Quickstart

You're an IRIS Platform Lead managing an HSCUSTOM (or plain-IRIS) interop namespace. Every time something goes sideways in production — a partner's HL7 admit silently rejected, a rule fire that didn't, a queue that stalled — you reconstruct the cross-surface picture in your head: `Ens.MessageHeader`, the body class, `Ens.Util.Log`, `Ens.Rule.Log`, BP runtime state. iris-session-agent embeds an AI assistant chat experience directly into the operator surfaces you already use, so *"what happened?"* gets answered with citations back to the underlying log rows. This quickstart walks the install + verify path end-to-end in ~30 minutes.

> [!NOTE]
> The current build ships **Epic 1** only — installable foundation, RBAC role, audit-event scaffolding. The chat tab, agent runtime, and configuration UI land in Epics 2–6. This quickstart honestly reflects what works **today** vs. what's coming. For the whole product, wait for the MVP-complete tag at end of Epic 4.

## 1. Run through the prerequisite checklist

Open [README.md §"Operator Prerequisites"](../README.md#operator-prerequisites) and complete the nine one-time setup steps. **Three of them are install-blocking or first-call-blocking** — get these right or `zpm install` will fail or the very first agent turn will produce a sub-second "mid-flight failure" with no real network call:

- **§2 IPM availability.** On a fresh IRIS for Health, `zpm` is installed only in `%SYS` (and a read-only DeveloperMode copy in `HSLIB`). Your target namespace (HSCUSTOM, USER, etc.) starts unmapped. Run from `%SYS`: `Do $System.OBJ.Load("https://pm.community.intersystems.com/packages/zpm/latest/installer","ck")` (skip if `zpm version` already works in `%SYS`), then `zpm "enable -map -globally"`. Verify with `zpm version` from your target namespace — should report the same version as `%SYS`.
- **§3 Web Gateway timeout 60 → 300s.** LLM calls routinely run 30–90s; an agent turn chains 2–3 of them. The default 60s ceiling kills agent turns mid-stream. Path: Web Gateway management page → Configuration → Default Parameters → "Server Response Timeout" → 300.
- **§7 SSL/TLS configuration `DefaultSSL`.** The OpenAIProvider issues HTTPS POSTs and references an SSL configuration named **`DefaultSSL`**. If that name is not present in `Security.SSLConfigs`, the very first agent turn fails fast with `"OpenAI mid-flight failure"` (no actual HTTPS call happens — IRIS rejects the request at the SSL-config-lookup step). Mgmt Portal path: *System Administration → Security → SSL/TLS Configurations → Create New Configuration → Name=`DefaultSSL`, Type=`Client`, Min Protocol=`TLSv1.2`*. Verify with `SELECT Name FROM Security.SSLConfigs` from `%SYS`.

The other six prereqs (IRIS version, RBAC role assignment, package mapping, API key, bookmark URLs, daily purge task) are documented in the README and don't need to be redone here.

## 2. Run `zpm install iris-session-agent`

From your target namespace (e.g., HSCUSTOM):

```
zpm "load /path/to/iris-session-agent"
```

If the prereqs are in place, you'll see all six IPM lifecycle phases SUCCESS. The Configure phase prints the install hooks' output:

```
[HSCUSTOM|iris-session-agent]   Configure START
[iris-session-agent] SessionAgent.Task.PurgeOrphanedChatHistory not yet implemented; sweep deferred
[iris-session-agent] SessionAgent.Task.PurgeStaleSearchChat not yet implemented; sweep deferred
[iris-session-agent] SessionAgent.Task.UserVocabularyDecay not yet implemented; sweep deferred
[iris-session-agent] SessionAgent.Config.Agent not yet implemented; default configs deferred
=== iris-session-agent install reminders ===
Bookmark URLs (HealthShare):
  /csp/healthshare/HSCUSTOM/SessionAgent.EnsPortal.VisualTrace.zen
  /csp/healthshare/HSCUSTOM/SessionAgent.EnsPortal.MessageViewer.zen
Bookmark URLs (plain IRIS):
  /csp/HSCUSTOM/SessionAgent.EnsPortal.VisualTrace.zen
  /csp/HSCUSTOM/SessionAgent.EnsPortal.MessageViewer.zen
See README "Operator Prerequisites" for one-time setup (Web Gateway timeout 60->300, RBAC role assignment, API key supply).
===========================================
[HSCUSTOM|iris-session-agent]   Configure SUCCESS
```

The four `not yet implemented; sweep/configs deferred` lines are **expected** in the Epic 1 build — those classes ship in later stories (sweep tasks in Epics 7 + 10, default configs in Epic 2). The single `<CSPApplication>` deprecation warning above the lifecycle output is informational, not an error.

## 3. Bookmark a known-failed session

Pick the bookmark URL pattern matching your deployment style (HealthShare or plain-IRIS) and substitute your namespace. Example for plain-IRIS HSCUSTOM:

```
/csp/HSCUSTOM/SessionAgent.EnsPortal.VisualTrace.zen
```

You'll need a known-failed Ens session to navigate to. The fastest way to find one: in the Management Portal, open Interoperability → View → Event Log, filter by Type=Error, copy the session ID from the most recent error row. Append the session as a URL parameter to the bookmark, the same way you would for the standard `EnsPortal.VisualTrace.zen` page.

## 4. Open the chat tab — what to expect TODAY

**Honest disclosure:** in the Epic 1 build, the bookmark URL works (the install printed it; the namespace mapping resolves), but the destination page is **still the standard `EnsPortal.VisualTrace`** — there is no `SessionAgent.EnsPortal.VisualTrace` Zen subclass yet. Epic 3 (Stories 3.1–3.7) ships the chat panel + the subclass that adds the chat tab to Visual Trace; Epic 6 (Stories 6.1–6.3) ships the per-agent configuration UI; Epic 4 closes out the full inspection-tool catalogue.

So step 4 today is: confirm the URL navigates without error and you land on the operator's familiar Visual Trace page. **The chat tab arrives in the Epic 3 build.** Once it lands, the no-config empty state will prompt you with a one-click link to the agent configuration page (Epic 6 — Story 6.3 wires the link).

## 5. Verify the install via SQL

Until the audit ledger tables ship in Story 2.5, verify install via the actual state Stories 1.3 and 1.4 created. Run from `%SYS`:

```sql
-- Confirm Story 1.3 audit-event triples are registered
SELECT Source, Type, Name FROM Security.Events WHERE Source = 'SessionAgent'
-- Expected: 11 rows (4 LlmCall providers + 4 VocabWrite enums + 3 TaskRun task names)

-- Confirm Story 1.4 RBAC role exists
SELECT Name, Description FROM Security.Roles WHERE Name = 'SessionAgent_ReadOnly'
-- Expected: 1 row, Description = "Read-only access to Ens.* tables for iris-session-agent"
```

If both queries return the expected row counts, your Epic 1 install is correct. After Story 2.5 ships the audit ledger tables, this verification expands to include `SELECT TOP 0 * FROM SessionAgent_Audit.LlmCall` and `SELECT TOP 0 * FROM SessionAgent_Audit.ToolCall` — both should return empty result sets confirming the schemas are in place.

## 6. Switching to self-hosted (Ollama / vLLM / LM Studio)

Per-token LLM cost is the most common adoption blocker. Once Epic 5 lands you can point the runtime at any **OpenAI-Chat-Completions-compatible** endpoint hosted inside your own perimeter — no per-token cost, your data never leaves your VPC. The provider is the same `SessionAgent.LLM.OpenAICompatProvider` shipped by Story 5.3; you only swap the `Config.Agent` row's `EndpointUrl` and `Model` fields.

Smallest configuration change (per the README §6 table):

```
Provider        = openai-compatible
EndpointUrl     = http://<host>:11434/v1/chat/completions   ; e.g. http://192.168.0.123:11434/...
Model           = qwen3:14b                                 ; or any model your endpoint serves
CredentialName  = ''                                        ; leave empty for default Ollama (no auth)
EnvVarName      = PATH                                      ; satisfies abstract template; ignored when CredentialName empty
```

For paid OpenAI-compatible providers (Together AI, OpenRouter, Anyscale) set `CredentialName='YourCredential'` and create the matching `Ens.Config.Credentials` row with a Bearer token in `Password`. For HTTPS endpoints (vLLM behind reverse-proxy, paid hosted), the same `DefaultSSL` configuration the README §7 documents covers TLS — the provider auto-detects scheme + non-default port from the URL. See **README §6** for the full deployment table and provider-comparison rationale.

---

## What's next

You've got an installable foundation that reinstalls idempotently with `zpm load`, an audit-event registry ready for the LLM and tool-call audit rows that Epic 2 fills in, and a read-only RBAC role enforcing Layer 3 of the read-only invariant at the IRIS database privilege layer. Epic 2 backend, Epic 3 first-delight chat demo, Epic 4 full tool catalogue, and Epic 6 configuration UI are the next milestones — [`epics.md`](../_bmad-output/planning-artifacts/epics.md) has the full sprint plan.

Stuck on a step? File an issue with the install log snippet and the SQL verification output — that's enough information to diagnose 90% of install-time problems.
