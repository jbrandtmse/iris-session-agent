/// <p>Unit tests for <CLASS>SessionAgent.Audit.Emit</CLASS>.</p>
///
/// <p>Verifies the three behaviors required by Story 1.3 acceptance
/// criterion AC-3:</p>
/// <ol>
/// <li><b>TestEnsureEventsRegistersAllEleven</b> — every concrete (Source,
/// Type, Name) triple specified by the architecture is present in the
/// <code>%SYS Security.Events</code> registry after a single
/// <code>EnsureEvents()</code> call.</li>
/// <li><b>TestEnsureEventsIdempotent</b> — calling
/// <code>EnsureEvents()</code> twice in succession leaves the registry in
/// the same state (same triples present, status <code>$$$OK</code> both
/// times).</li>
/// <li><b>TestEnsureEventsRestoresNamespace</b> — the caller's
/// <code>$NAMESPACE</code> is unchanged after the call (the success-path
/// half of the explicit save/restore pattern).</li>
/// </ol>
///
/// <p>Test methods that need to query <code>Security.Events.Exists</code>
/// use the same explicit save/restore pattern that
/// <code>SessionAgent.Audit.Emit</code> uses, so the test does not pollute
/// <code>$NAMESPACE</code> on exit.</p>
Class SessionAgent.Test.AuditEmitTest Extends %UnitTest.TestCase
{

/// <p>Constructor — must accept the <code>initvalue</code> parameter the
/// parent <code>%UnitTest.TestCase</code> expects, and must call
/// <code>##super(initvalue)</code>. No <code>Private</code> keyword
/// (per project rule §"Critical Constructor Requirements").</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>AC-3 #1 — invoke <code>EnsureEvents()</code> and assert every one
/// of the eleven concrete triples is present in the
/// <code>%SYS Security.Events</code> registry.</p>
Method TestEnsureEventsRegistersAllEleven()
{
    Do $$$AssertStatusOK(##class(SessionAgent.Audit.Emit).EnsureEvents(), "EnsureEvents returns OK")

    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"

        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","LlmCall","openai"), "LlmCall/openai registered")
        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","LlmCall","anthropic"), "LlmCall/anthropic registered")
        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","LlmCall","gemini"), "LlmCall/gemini registered")
        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","LlmCall","ollama"), "LlmCall/ollama registered")

        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","VocabWrite","clickthrough"), "VocabWrite/clickthrough registered")
        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","VocabWrite","explicit"), "VocabWrite/explicit registered")
        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","VocabWrite","extracted"), "VocabWrite/extracted registered")
        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","VocabWrite","seed"), "VocabWrite/seed registered")

        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","TaskRun","PurgeOrphanedChatHistory"), "TaskRun/PurgeOrphanedChatHistory registered")
        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","TaskRun","PurgeStaleSearchChat"), "TaskRun/PurgeStaleSearchChat registered")
        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","TaskRun","UserVocabularyDecay"), "TaskRun/UserVocabularyDecay registered")

        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Do $$$AssertTrue(0, "Unexpected exception: " _ ex.DisplayString())
    }
    Quit
}

/// <p>AC-3 #2 — invoke <code>EnsureEvents()</code> twice. Both calls must
/// return <code>$$$OK</code>, and the registry must contain exactly one
/// entry per triple after the second call (no duplicates).</p>
///
/// <p>Note: <code>Security.Events</code> is keyed on the
/// (Source, Type, Name) triple, so the registry is structurally
/// incapable of holding duplicates — but a correct implementation must
/// also avoid calling <code>Create()</code> on an existing triple
/// (because <code>Create()</code> would return an error status for a
/// duplicate, which the second invocation must not surface).</p>
Method TestEnsureEventsIdempotent()
{
    Do $$$AssertStatusOK(##class(SessionAgent.Audit.Emit).EnsureEvents(), "first EnsureEvents() call OK")
    Do $$$AssertStatusOK(##class(SessionAgent.Audit.Emit).EnsureEvents(), "second EnsureEvents() call OK (no duplicate-create error)")

    ; Spot-check one triple from each Type after the second call to confirm
    ; the registry is still well-formed.
    Set tOrigNS = $NAMESPACE
    Try {
        Set $NAMESPACE = "%SYS"
        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","LlmCall","openai"), "LlmCall/openai still present after second call")
        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","VocabWrite","seed"), "VocabWrite/seed still present after second call")
        Do $$$AssertTrue(##class(Security.Events).Exists("SessionAgent","TaskRun","PurgeOrphanedChatHistory"), "TaskRun/PurgeOrphanedChatHistory still present after second call")
        Set $NAMESPACE = tOrigNS
    }
    Catch ex {
        Set $NAMESPACE = tOrigNS
        Do $$$AssertTrue(0, "Unexpected exception: " _ ex.DisplayString())
    }
    Quit
}

/// <p>AC-3 #3 — capture <code>$NAMESPACE</code> before the call, invoke
/// <code>EnsureEvents()</code>, and verify <code>$NAMESPACE</code> is
/// unchanged afterward (success-path coverage of the save/restore
/// pattern).</p>
Method TestEnsureEventsRestoresNamespace()
{
    Set tBefore = $NAMESPACE
    Do $$$AssertStatusOK(##class(SessionAgent.Audit.Emit).EnsureEvents(), "EnsureEvents OK")
    Do $$$AssertEquals($NAMESPACE, tBefore, "namespace restored after EnsureEvents()")
    Quit
}

}
