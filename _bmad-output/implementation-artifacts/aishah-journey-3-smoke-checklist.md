# Aishah Journey 3 — End-to-End Configure-and-Ask Smoke Checklist

**Story 6.3 deliverable.** This is the operator-style manual walkthrough the
lead executes at the Epic 6 empirical battery (Rule 6 step 4 + Rule 12
human-read step). Story 6.3 ships the structural enabler — the real `<a>`
anchor in the chat-panel empty state — that this checklist exercises end to
end.

**Epic 6 acceptance gate (verbatim from sprint planning):**
*"Per-agent config UI is end-to-end usable; no SQL editing required;
Aishah Journey 3 enacted on a real install."*

**Walkthrough target.** The 6 steps below complete within the **30-minute
Aishah-walkthrough target per NFR-O1** (informally validated by the lead
during the empirical battery; Story 6.3 is the structural enabler, not the
timing test).

## Pre-state

- [ ] Fresh-install state confirmed: either `SessionAgent.Config.Agent("session-inspection")` is missing from the `SessionAgent_Config.Agent` table, OR the row exists with `Enabled = 0`.
  - SQL probe to confirm:
    ```sql
    SELECT %EXACT(Name) AS Name, Enabled, Provider, Model
    FROM SessionAgent_Config.Agent
    WHERE %EXACT(Name) = 'session-inspection'
    ```
  - Expected: 0 rows OR 1 row with `Enabled=0`.
- [ ] No `Ens.Config.Credentials` entry for OpenAI, OR the entry exists but is unreferenced. (The next step relies on `OpenAIDev` already being seeded — the lead's pre-cycle setup per Rule 7 ensures this.)
- [ ] Mgmt-Portal admin browser session active (operator has the `%All` role or the `SessionAgent_Admin` role + portal access).

## Step 1 — Open Visual Trace, navigate to chat tab

- [ ] Navigate to **System Operation → Interoperability → Visual Trace** (or the URL `/csp/<ns>/SessionAgent.EnsPortal.VisualTrace.zen?SESSIONID=<any-session>`).
- [ ] Click the **Chat** tab.
- [ ] Verify the chat panel renders the **`sa-config-empty-prompt` empty state** with the new `<a>` anchor:
  - Visible text: **"This agent isn't configured yet. Configure agent →"**
  - The "Configure agent →" portion is a **link** (underlined / hover cursor).
  - The `→` arrow renders as a real **U+2192 RIGHTWARDS ARROW** glyph (NOT mojibake `â†'`, NOT `Ã¢â€ â€™`, NOT `?`).
- [ ] **Rule 12 human-read:** read the rendered string aloud — it MUST be readable English with the arrow glyph rendering correctly. Take a screenshot via `chrome-devtools-mcp` `take_screenshot` if available; fall back to a rendered-DOM `textContent` paste.

## Step 2 — Click the "Configure agent →" anchor

- [ ] Click the link.
- [ ] Browser navigates to **`/csp/<lower-namespace>/SessionAgent.UI.AgentConfig.zen`** (where `<lower-namespace>` is the runtime-resolved lowercased namespace — e.g., `hscustom` on a stock install, `otherns` on a non-stock install).
- [ ] The Story 6.1 AgentConfig zen form loads with the empty / default field values.

## Step 3 — Fill the AgentConfig form

- [ ] Set the form fields:
  - **Provider** = `OpenAI`
  - **Model** = `gpt-4.1-mini`
  - **CredentialName** = `OpenAIDev` (assumed pre-seeded in `Ens.Config.Credentials` per Rule 7 operator setup)
  - **MaxTokens** = `4000`
  - **Temperature** = `0.1`
  - **Enabled** = `1` (checked)
- [ ] Click **Save**.
- [ ] The Story 6.2 save handler returns success and the form remains on the page (no error banner).

## Step 4 — Return to Visual Trace

- [ ] Click the browser **back button** (or navigate to Visual Trace's chat tab directly).
- [ ] The chat panel **re-detects config presence** and now shows the **normal first-time empty state**:
  - Welcome message visible.
  - The input textarea is **enabled** and **auto-focused**.
  - The `sa-config-empty-prompt` div from Step 1 is **gone**.

## Step 5 — Send a "ping" message

- [ ] Type **`ping`** in the input.
- [ ] Press **Enter** (or click the submit affordance).
- [ ] The agent dispatches and returns a **real LLM response** within ~10 seconds.
- [ ] No HTTP 4xx / 5xx error envelope appears.

## Step 6 — Confirm round-trip reproducibility

- [ ] Type a second message (e.g., `What sessions are in this namespace?`).
- [ ] The agent invokes one of the inspection tools (per the welcome message's "Use only the tools in the list provided" directive — Story 4.0 / Epic 3 retro AI-15) and returns a substantive response with citation chips.
- [ ] Visual Trace's chat tab is **end-to-end usable** without any SQL editing or admin-portal class-edit step.

## Sign-off

The lead initials each checkbox above as the walkthrough proceeds.
A clean run (every box ticked, total elapsed time under 30 min, U+2192
arrow renders correctly, no mojibake artifacts) is the **Epic 6 acceptance
gate** — signaling the per-agent config UI is end-to-end usable on a real
install.

| Field | Value |
|---|---|
| Lead | (initials) |
| Date | (YYYY-MM-DD) |
| Elapsed time | (mm:ss) |
| IRIS namespace | (e.g., `HSCUSTOM`) |
| Browser | (e.g., Chrome 132) |
| OpenAI model used | `gpt-4.1-mini` |
| Notes | (any anomalies) |

## References

- [Story 6.3 spec](6-3-replace-placeholder-admin-link-end-to-end-configure-and-ask-validation.md)
- [`epic-cycle-discipline.md` Rule 12](../../.claude/rules/epic-cycle-discipline.md) — rendered-text human-read evidence requirement.
- `prd.md` NFR-O1 — 30-minute Aishah-walkthrough target.
- `prd.md` UX-DR7-admin / UX-DR19 / UX-DR20 — admin-only language, real-anchor, aria-label invariants.
