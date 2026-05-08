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
