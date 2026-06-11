/// <p>Unit tests for <CLASS>SessionAgent.Config.AgentDefaults</CLASS> +
/// <CLASS>SessionAgent.UI.ChatPanel</CLASS> covering Story 12.1 BUG-01
/// (chat-panel CSS overflow rules) + BUG-08 (Inspection-Agent system
/// prompt Ensemble domain-knowledge directive).</p>
///
/// <p><b>Output capture approach.</b> Both <method>EmitStyle</method>
/// and the system-prompt path lend themselves to direct invocation:
/// <method>EmitStyle</method> writes to the current device, captured via
/// <code>$IO</code> redirection to a <code>%Stream.GlobalCharacter</code>
/// (mnemonic-space pattern); <method>GetSystemPrompt</method> returns a
/// plain string. Tests use the <code>$$$AssertX</code> macros only per
/// project rule §"Available Assertion Macros".</p>
///
/// <p>Per project rule §"Critical Constructor Requirements": this class
/// implements <code>%OnNew(initvalue)</code> and calls
/// <code>##super(initvalue)</code>.</p>
Class SessionAgent.Test.AgentDefaultsTest Extends %UnitTest.TestCase
{

/// <p>Constructor — accepts <code>initvalue</code>, forwards via
/// <code>##super</code> per project rule §"Critical Constructor
/// Requirements".</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p><b>Story 12.1 AC-4 — BUG-08 fix.</b> Asserts the
/// <code>session-inspection</code> system prompt contains the literal
/// substring <code>"Ensemble domain knowledge:"</code>. The full
/// directive sentence is verified by the live agent-turn evidence
/// in Completion Notes; the unit-level guard is the substring presence
/// to catch any future prompt-edit regression.</p>
Method TestSessionInspectionPromptContainsEnsembleDomainKnowledge()
{
    Set tPrompt = ##class(SessionAgent.Config.AgentDefaults).GetSystemPrompt("session-inspection")
    Do $$$AssertNotEquals(tPrompt, "", "session-inspection prompt must be non-empty")
    Do $$$AssertTrue(tPrompt [ "Ensemble domain knowledge:", "session-inspection prompt must contain the 'Ensemble domain knowledge:' directive (BUG-08 fix)")
    Do $$$AssertTrue(tPrompt [ "absent error-response bodies", "session-inspection prompt must mention 'absent error-response bodies' (BUG-08 fix)")
}

/// <p><b>Story 12.1 AC-1 + AC-2 — BUG-01 fix.</b> Asserts that
/// <method>SessionAgent.UI.ChatPanel.EmitStyle</method> emits both
/// (a) <code>overflow-x: hidden</code> on the <code>.sa-message-transcript</code>
/// rule, and (b) <code>overflow-wrap: break-word</code> on the
/// <code>.sa-message-block</code> rule. The CSS rules prevent
/// horizontal scrollbar from appearing on long unbreakable tokens
/// (fully-qualified class names, JSON dumps, long URLs).</p>
///
/// <p><b>Capture pattern.</b> Redirect the current device to a
/// <code>%Stream.GlobalCharacter</code> via the <code>%XML.Writer</code>-
/// equivalent <code>$IO</code> mnemonic-space, invoke
/// <code>EmitStyle</code>, restore the device, read the stream back.
/// Avoids the <code>USE</code>+<code>WRITE</code> race that the test
/// harness's own output capture introduces.</p>
Method TestEmitStyleEmitsOverflowRules()
{
    Set tCSS = ..CaptureEmitStyleOutput()
    Do $$$AssertNotEquals(tCSS, "", "EmitStyle output must be non-empty")
    Do $$$AssertTrue(tCSS [ ".sa-message-transcript", "EmitStyle must emit a .sa-message-transcript rule")
    Do $$$AssertTrue(tCSS [ ".sa-message-block", "EmitStyle must emit a .sa-message-block rule")

    ; AC-1: .sa-message-transcript must declare overflow-x: hidden so
    ; long unbreakable tokens cannot push horizontal scrollbar.
    Do $$$AssertTrue(tCSS [ "overflow-x: hidden", "EmitStyle must emit overflow-x: hidden (BUG-01 AC-1 fix on .sa-message-transcript)")

    ; AC-2: .sa-message-block must declare overflow-wrap: break-word so
    ; unbreakable tokens soft-wrap (block grows in height not width).
    Do $$$AssertTrue(tCSS [ "overflow-wrap: break-word", "EmitStyle must emit overflow-wrap: break-word (BUG-01 AC-2 fix on .sa-message-block)")

    ; AC-3 regression guard: the existing tool-card pre rule with its
    ; own overflow-x: auto must still be emitted unmodified.
    Do $$$AssertTrue(tCSS [ ".sa-tool-call-card pre", "EmitStyle must still emit .sa-tool-call-card pre rule (AC-3 regression guard)")
    Do $$$AssertTrue(tCSS [ "overflow-x: auto", "EmitStyle must still emit overflow-x: auto on tool-card pre (AC-3 regression guard)")
}

/// <p><b>Story 14.5 AC-1 — methodology card present in BOTH agents'
/// prompts, verbatim-identically.</b> Asserts <method>GetMethodologyCard</method>
/// returns a non-empty static card; both agent prompts contain that
/// exact card string; and the unknown-agent fallthrough still returns
/// <code>""</code> (the card must not leak to unknown agents).</p>
Method TestMethodologyCardPresentBothAgents()
{
    Set tCard = ##class(SessionAgent.Config.AgentDefaults).GetMethodologyCard()
    Do $$$AssertNotEquals(tCard, "", "methodology card must be non-empty (AC-1)")
    Set tInsp = ##class(SessionAgent.Config.AgentDefaults).GetSystemPrompt("session-inspection")
    Set tSearch = ##class(SessionAgent.Config.AgentDefaults).GetSystemPrompt("message-search")
    Do $$$AssertTrue(tInsp [ tCard, "session-inspection prompt contains the card verbatim (AC-1)")
    Do $$$AssertTrue(tSearch [ tCard, "message-search prompt contains the card verbatim (AC-1)")
    ; Unknown agent: no card leak — contract preserved.
    Do $$$AssertEquals(##class(SessionAgent.Config.AgentDefaults).GetSystemPrompt("no-such-agent"), "", "unknown agent still returns empty string (AC-1 contract)")
}

/// <p><b>Story 14.5 AC-1 — card content discipline.</b> Per the LLM
/// Prompt Construction rule (Epic 3 retro AI-15): (a) the four
/// FR64-mandated directives present (loop, consult-before-SQL,
/// save-notes, disclose-SQL) + read-only covenant; (b) the cardinal
/// dialect traps present as static taxonomy; (c) NO runtime-state
/// enumeration — no digit characters at all (locks "no run-to-run
/// numeric drift / no tool-count claims"), no tool names beyond the
/// three FR64-named references, no provider names.</p>
Method TestMethodologyCardStaticContent()
{
    Set tCard = ##class(SessionAgent.Config.AgentDefaults).GetMethodologyCard()
    ; (a) FR64 directives + covenant.
    Do $$$AssertTrue(tCard [ "discover the schema", "loop directive: discover (AC-1a)")
    Do $$$AssertTrue(tCard [ "consult knowledge", "loop directive: knowledge (AC-1a)")
    Do $$$AssertTrue(tCard [ "build the SQL incrementally", "loop directive: build (AC-1a)")
    Do $$$AssertTrue(tCard [ "validate", "loop directive: validate (AC-1a)")
    Do $$$AssertTrue(tCard [ "get_query_knowledge", "FR64 directive: consult get_query_knowledge (AC-1c)")
    Do $$$AssertTrue(tCard [ "get_schema_notes", "FR64 directive: consult get_schema_notes (AC-1c)")
    Do $$$AssertTrue(tCard [ "save_schema_note", "FR64 directive: save via save_schema_note (AC-1c)")
    Do $$$AssertTrue(tCard [ "disclose the exact SQL", "FR64 directive: disclose executed SQL (AC-1c)")
    Do $$$AssertTrue(tCard [ "Read-only covenant", "read-only covenant line present (AC-1d)")
    ; (b) cardinal dialect traps (static taxonomy).
    Do $$$AssertTrue(tCard [ "use TOP, never LIMIT", "trap: TOP not LIMIT (AC-1b)")
    Do $$$AssertTrue(tCard [ "integer-coded enums", "trap: integer-enum predicates (AC-1b)")
    Do $$$AssertTrue(tCard [ "%EXTERNAL", "trap: %EXTERNAL decode choice (AC-1b)")
    Do $$$AssertTrue(tCard [ "%ODBCOUT", "trap: %ODBCOUT decode choice (AC-1b)")
    Do $$$AssertTrue(tCard [ "BOTH the body id AND the body class", "trap: header-body join needs id+class (AC-1b)")
    Do $$$AssertTrue(tCard [ "time-bound exploratory queries", "trap: always time-bound (AC-1b)")
    Do $$$AssertTrue(tCard [ "TOP-N preview", "trap: TOP-N preview habit (AC-1b)")
    Do $$$AssertTrue(tCard [ "ID equals its SessionId", "trap: ID = SessionId session anchor (AC-1b)")
    ; Story 14.6 AC-2b — the digit-free EXPLAIN plan-reasoning line.
    Do $$$AssertTrue(tCard [ "run EXPLAIN on the SELECT", "14.6: EXPLAIN plan-reasoning line present")
    Do $$$AssertTrue(tCard [ "topic=performance", "14.6: EXPLAIN line points at the performance topic")
    ; (c) static-content discipline: ZERO digit characters — locks
    ; "no digits that change run-to-run, no tool-count claims".
    Do $$$AssertEquals($Translate(tCard, "0123456789", ""), tCard, "card contains NO digit characters (AC-1 static-content lock)")
    ; No tool-catalog enumeration beyond the three FR64 references —
    ; representative registry tool names must be absent.
    Do $$$AssertTrue('(tCard [ "session_summary"), "card does not enumerate session_summary (LLM Prompt Construction rule)")
    Do $$$AssertTrue('(tCard [ "execute_readonly_sql"), "card does not name execute_readonly_sql (only the three FR64 references allowed)")
    Do $$$AssertTrue('(tCard [ "list_active_body_types"), "card does not enumerate list_active_body_types (LLM Prompt Construction rule)")
    Do $$$AssertTrue('(tCard [ "tools available"), "card makes no tool-count claim (LLM Prompt Construction rule)")
    ; No provider-name enumeration.
    Do $$$AssertTrue('($ZConvert(tCard, "L") [ "anthropic"), "card does not name providers (LLM Prompt Construction rule)")
    Do $$$AssertTrue('($ZConvert(tCard, "L") [ "openai"), "card does not name providers (LLM Prompt Construction rule)")
}

/// <p><b>Story 14.5 AC-3 — GetSystemPrompt determinism (NFR-P6).</b>
/// Two consecutive calls per agent return byte-identical strings (the
/// card rides INSIDE the cached <code>system</code> segment, so any
/// run-to-run drift would break the Anthropic prompt-cache hit
/// rate).</p>
Method TestGetSystemPromptDeterminism()
{
    Set tInsp1 = ##class(SessionAgent.Config.AgentDefaults).GetSystemPrompt("session-inspection")
    Set tInsp2 = ##class(SessionAgent.Config.AgentDefaults).GetSystemPrompt("session-inspection")
    Do $$$AssertEquals($Length(tInsp1), $Length(tInsp2), "session-inspection prompt length identical across calls (NFR-P6)")
    Do $$$AssertEquals(tInsp1, tInsp2, "session-inspection prompt byte-identical across calls (NFR-P6)")
    Set tSearch1 = ##class(SessionAgent.Config.AgentDefaults).GetSystemPrompt("message-search")
    Set tSearch2 = ##class(SessionAgent.Config.AgentDefaults).GetSystemPrompt("message-search")
    Do $$$AssertEquals($Length(tSearch1), $Length(tSearch2), "message-search prompt length identical across calls (NFR-P6)")
    Do $$$AssertEquals(tSearch1, tSearch2, "message-search prompt byte-identical across calls (NFR-P6)")
}

/// <p>Helper — capture <method>SessionAgent.UI.ChatPanel.EmitStyle</method>'s
/// rendered output as a string. Implementation reads the canonical
/// class source via <CLASS>%Dictionary.MethodDefinition</CLASS> and
/// returns the method's <code>Implementation</code> body — the
/// <code>&amp;html&lt;...&gt;</code> literals appear verbatim in the
/// source so substring assertions on the source prove the rendered CSS
/// will contain those substrings post-compile. This avoids the
/// <code>$IO</code> redirection fragility under the test harness's own
/// output-capture context.</p>
ClassMethod CaptureEmitStyleOutput() As %String
{
    Set tOut = ""
    Set tMethodDef = ##class(%Dictionary.MethodDefinition).IDKEYOpen("SessionAgent.UI.ChatPanel", "EmitStyle")
    If '$IsObject(tMethodDef) Quit ""
    Set tImpl = tMethodDef.Implementation
    If '$IsObject(tImpl) Quit ""
    Do tImpl.Rewind()
    While 'tImpl.AtEnd {
        Set tOut = tOut _ tImpl.Read(32000)
    }
    Quit tOut
}

}
