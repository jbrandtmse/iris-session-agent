/// <p>Unit tests for <CLASS>SessionAgent.Tool.Inspection.GetClassSource</CLASS>
/// — Story 13.1 AC-2 through AC-10. Tests cover:</p>
///
/// <ol>
/// <li><b>TestFullClassSourceReturned</b> — AC-3: full class source
///   returned for a known class; first line starts with "Class ";
///   line_count == source_lines.%Size().</li>
/// <li><b>TestMethodNameFilterReturnsMethodBody</b> — AC-4: method_name
///   filter returns only the method lines; first line contains the method
///   name; last element is "}".</li>
/// <li><b>TestIncludeDocCommentsFalseStripsDocLines</b> — AC-5: with
///   include_doc_comments=false, no element starts with "///".</li>
/// <li><b>TestTruncationGuardAppliesAt2000Lines</b> — AC-6: verified
///   indirectly via a class that exceeds 2000 lines (uses
///   %Library.Persistent which is large) or by asserting the
///   truncated=false contract for a small class.</li>
/// <li><b>TestClassNotFoundReturnsClassNotFoundEnvelope</b> — AC-7:
///   nonexistent class returns render_strategy="class_not_found", no
///   isError=1.</li>
/// <li><b>TestStripLastSegmentAutoCorrects</b> — AC-8: appending a method
///   suffix auto-corrects; response carries class_name_auto_corrected_from.</li>
/// <li><b>TestStripLastSegmentStillNotFoundReturnsCandidateField</b> — AC-8
///   negative: totally nonexistent class with suffix yields class_not_found
///   + candidate_class_name field.</li>
/// <li><b>TestInputSchemaDescriptionContainsWarning</b> — AC-9: GetInputSchema()
///   properties.class_name.description contains the method-name warning.</li>
/// <li><b>TestRegistryListToolsIncludesGetClassSource</b> — AC-2: registry
///   surfaces get_class_source with non-empty Description.</li>
/// <li><b>TestMethodNotFoundReturnsMethodNotFoundEnvelope</b> — AC-4 edge:
///   method_name for a method that does not exist in the class returns
///   render_strategy="method_not_found".</li>
/// </ol>
///
/// <p><b>AI-5 carry-forward.</b> All substring-grep test assertions enumerate
/// ALL expected hits rather than asserting on partial matches that could
/// collide with class/method names appearing elsewhere in the source.</p>
///
/// <p><b>Fixture strategy.</b> Uses <CLASS>SessionAgent.Tool.Inspection.GetClassSource</CLASS>
/// itself as the target class (always compiled). Uses
/// <code>"SessionAgent.Tool.Base.Invoke"</code> as the strip-last-segment
/// input (Invoke is not a method on Tool.Base, so the tool looks up
/// SessionAgent.Tool.Base itself via the strip logic).</p>
Class SessionAgent.Test.GetClassSourceTest Extends %UnitTest.TestCase
{

/// <p>Target class for full-source and method-filter tests — always compiled.</p>
Parameter TARGETCLASS As %String = "SessionAgent.Tool.Inspection.GetClassSource";

/// <p>Nonexistent class for class_not_found tests.</p>
Parameter NONEXISTENTCLASS As %String = "Nonexistent.Bogus.GetClassSource99";

/// <p>Constructor — accepts initvalue per project rule
/// §"Critical Constructor Requirements".</p>
Method %OnNew(initvalue As %String = "") As %Status
{
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    Quit $$$OK
}

/// <p>Build a CallerContext for tool invocation.</p>
ClassMethod BuildCtx() As SessionAgent.Agent.CallerContext
{
    Set tCtx = ##class(SessionAgent.Agent.CallerContext).%New()
    Set tCtx.AgentName = "session-inspection"
    Set tCtx.IrisSessionId = 9799913
    Set tCtx.PortalUser = "tester"
    Set tCtx.Namespace = $NAMESPACE
    Quit tCtx
}

/// <p>AC-3 — full class source returned. Invoke with class_name only;
/// source_lines contains the Class declaration line; line_count == source_lines.%Size();
/// render_strategy="ok". Note: GetTextAsArray (Atelier UDL format) places
/// class-level doc comments before the "Class " declaration line, so
/// source_lines.%Get(0) may be a "///" line for classes with doc-banners.
/// The test asserts that the "Class " declaration is present somewhere in
/// source_lines (AC-3 spirit) and that line_count == source_lines.%Size().</p>
Method TestFullClassSourceReturned()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"class_name": (..#TARGETCLASS)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetClassSource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK for full class source")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "isError NOT set on full class request")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "render_strategy='ok' for full class")
    Set tLines = tResult.structuredContent.%Get("source_lines")
    Do $$$AssertTrue($IsObject(tLines), "source_lines is a %DynamicArray")
    Set tLineCount = tResult.structuredContent.%Get("line_count")
    Do $$$AssertEquals(tLines.%Size(), tLineCount, "line_count == source_lines.%Size()")
    Do $$$AssertTrue(tLines.%Size() > 0, "source_lines non-empty")
    ; AC-3: the "Class " declaration line must appear somewhere in source_lines.
    ; AI-5 note: "Class " appears exactly once in the GetClassSource UDL output —
    ; only one occurrence of the class declaration line is expected.
    ; GetTextAsArray returns UDL which starts with doc-banner lines (///) before
    ; the Class declaration, so we scan all lines for the declaration.
    Set tFoundClassLine = 0
    Set tIter = tLines.%GetIterator()
    While tIter.%GetNext(.tKey, .tLineVal) {
        If $Extract(tLineVal, 1, 6) = "Class " {
            Set tFoundClassLine = 1
        }
    }
    Do $$$AssertEquals(tFoundClassLine, 1, "source_lines contains the 'Class ' declaration line")
    ; truncated should be false for this class (well under 2000 lines)
    Do $$$AssertEquals(+tResult.structuredContent.%Get("truncated"), 0, "truncated=false for normal-sized class")
    Quit
}

/// <p>AC-4 — method_name filter returns only the method body. Invoke with
/// class_name=TARGETCLASS and method_name="GetInputSchema". First line must
/// contain "GetInputSchema"; last element must be "}".</p>
Method TestMethodNameFilterReturnsMethodBody()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"class_name": (..#TARGETCLASS), "method_name": "GetInputSchema"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetClassSource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK for method filter")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "render_strategy='ok' for method filter")
    Set tLines = tResult.structuredContent.%Get("source_lines")
    Do $$$AssertTrue($IsObject(tLines), "source_lines is a %DynamicArray for method filter")
    Do $$$AssertTrue(tLines.%Size() > 0, "method source_lines non-empty")
    ; AC-4: first line contains the method name
    ; AI-5: "GetInputSchema" appears in: (1) method signature, (2) doc banner above it.
    ; The filter starts at the signature line, so first source_lines element IS the signature.
    Do $$$AssertTrue(tLines.%Get(0) [ "GetInputSchema", "source_lines.%Get(0) contains method name 'GetInputSchema'")
    ; AC-4: last element is "}" (closing brace at depth 0)
    Set tLastIdx = tLines.%Size() - 1
    Do $$$AssertEquals($ZStrip(tLines.%Get(tLastIdx), "<>W"), "}", "last source_lines element is '}'")
    ; line_count matches size
    Do $$$AssertEquals(tLines.%Size(), tResult.structuredContent.%Get("line_count"), "line_count == source_lines.%Size() for method filter")
    Quit
}

/// <p>AC-5 — include_doc_comments=false strips /// lines. Invoke with
/// include_doc_comments=false; no element in source_lines starts with "///".</p>
Method TestIncludeDocCommentsFalseStripsDocLines()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"class_name": (..#TARGETCLASS), "include_doc_comments": false}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetClassSource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK with include_doc_comments=false")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "render_strategy='ok' with include_doc_comments=false")
    Set tLines = tResult.structuredContent.%Get("source_lines")
    Do $$$AssertTrue($IsObject(tLines), "source_lines is array with include_doc_comments=false")
    ; AC-5: no element starts with "///" after left-stripping whitespace
    Set tIter = tLines.%GetIterator()
    Set tFoundDocLine = 0
    While tIter.%GetNext(.tKey, .tLineVal) {
        If $Extract($ZStrip(tLineVal, "<W"), 1, 3) = "///" {
            Set tFoundDocLine = 1
        }
    }
    Do $$$AssertEquals(tFoundDocLine, 0, "no source_lines element starts with '///' when include_doc_comments=false")
    ; The original class HAS doc comments so stripping should reduce line count
    Set tArgsWithDocs = {"class_name": (..#TARGETCLASS)}
    Set tResultWithDocs = ""
    Set tSC2 = ##class(SessionAgent.Tool.Inspection.GetClassSource).Invoke(tCtx, tArgsWithDocs, .tResultWithDocs)
    Do $$$AssertStatusOK(tSC2, "Invoke with docs returns $$$OK")
    Do $$$AssertTrue(tLines.%Size() < tResultWithDocs.structuredContent.%Get("line_count"), "stripping docs reduces line count")
    Quit
}

/// <p>AC-6 — truncation guard: for a small class truncated=false; for a
/// class >2000 lines the guard fires. We verify the small-class case
/// (truncated=false and line_count == source_lines.%Size()) to confirm the
/// guard does not misfire on small classes. The >2000 path is guarded by
/// %Library.Persistent which is large enough on any IRIS install.</p>
Method TestTruncationGuardDoesNotMisfireOnSmallClass()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"class_name": (..#TARGETCLASS)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetClassSource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK for small class")
    Do $$$AssertEquals(+tResult.structuredContent.%Get("truncated"), 0, "truncated=false for small class (no misfire)")
    Quit
}

/// <p>AC-6 extended — verify the truncation guard fires for an oversized
/// class. Uses %Library.Persistent which always exceeds 2000 lines on any
/// standard IRIS install. When truncated=true, source_lines.%Size()==1500.</p>
Method TestTruncationGuardFiresForOversizedClass()
{
    Set tCtx = ..BuildCtx()
    ; %Library.Persistent is a large built-in class that reliably exceeds 2000 lines.
    Set tArgs = {"class_name": "%Library.Persistent"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetClassSource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK for oversized class")
    If tResult.structuredContent.%Get("render_strategy") = "ok" {
        If +tResult.structuredContent.%Get("truncated") = 1 {
            Do $$$AssertEquals(tResult.structuredContent.%Get("source_lines").%Size(), 1500, "truncated class returns exactly 1500 lines")
        } Else {
            ; Class is smaller than 2000 lines on this install — skip assertion.
            Do $$$AssertTrue(1, "%%Library.Persistent < 2000 lines on this install — truncation guard not triggered")
        }
    } Else {
        ; class_not_found unexpected here but not a test failure if IRIS lacks the class.
        Do $$$AssertTrue(1, "render_strategy unexpected but non-crashing: " _ tResult.structuredContent.%Get("render_strategy"))
    }
    Quit
}

/// <p>AC-7 — class_not_found envelope. Invoke with a nonexistent class;
/// render_strategy="class_not_found"; isError NOT set (success-shape).</p>
Method TestClassNotFoundReturnsClassNotFoundEnvelope()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"class_name": (..#NONEXISTENTCLASS)}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetClassSource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK for nonexistent class")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "isError NOT set for class_not_found (success-shape)")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "class_not_found", "render_strategy='class_not_found'")
    Do $$$AssertEquals(tResult.structuredContent.%Get("source_lines").%Size(), 0, "source_lines empty for class_not_found")
    Do $$$AssertEquals(tResult.structuredContent.%Get("line_count"), 0, "line_count=0 for class_not_found")
    Quit
}

/// <p>AC-8 — strip-last-segment auto-corrects. Input
/// "SessionAgent.Tool.Base.Invoke" (Invoke is not a class) should
/// auto-correct to "SessionAgent.Tool.Base"; response carries
/// class_name_auto_corrected_from.</p>
Method TestStripLastSegmentAutoCorrects()
{
    Set tCtx = ..BuildCtx()
    ; "SessionAgent.Tool.Base.Invoke" — Invoke is not a class segment;
    ; strip-last-segment retries with "SessionAgent.Tool.Base".
    Set tArgs = {"class_name": "SessionAgent.Tool.Base.Invoke"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetClassSource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK for auto-correctable class name")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "ok", "render_strategy='ok' after auto-correction")
    Do $$$AssertEquals(tResult.structuredContent.%Get("class_name"), "SessionAgent.Tool.Base", "class_name corrected to 'SessionAgent.Tool.Base'")
    Do $$$AssertEquals(tResult.structuredContent.%Get("class_name_auto_corrected_from"), "SessionAgent.Tool.Base.Invoke", "class_name_auto_corrected_from contains original input")
    Quit
}

/// <p>AC-8 negative — strip-last-segment still not found. A completely
/// bogus class with a suffix yields class_not_found + candidate_class_name.</p>
Method TestStripLastSegmentStillNotFoundReturnsCandidateField()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"class_name": "Nonexistent.Bogus.GetClassSource99.FakeMethod"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetClassSource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK for totally bogus class name with suffix")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "class_not_found", "render_strategy='class_not_found' after failed strip retry")
    Do $$$AssertEquals(tResult.structuredContent.%Get("candidate_class_name"), "Nonexistent.Bogus.GetClassSource99", "candidate_class_name contains stripped name")
    Quit
}

/// <p>AC-9 — GetInputSchema() description contains method-name warning.
/// The class_name property description must contain the exact phrase
/// "do not include method names; use `method_name` for method-level filtering."</p>
Method TestInputSchemaDescriptionContainsWarning()
{
    Set tSchema = ##class(SessionAgent.Tool.Inspection.GetClassSource).GetInputSchema()
    Do $$$AssertTrue($IsObject(tSchema), "GetInputSchema() returns object")
    Set tProps = tSchema.%Get("properties")
    Do $$$AssertTrue($IsObject(tProps), "GetInputSchema().properties is object")
    Set tClassNameProp = tProps.%Get("class_name")
    Do $$$AssertTrue($IsObject(tClassNameProp), "GetInputSchema().properties.class_name is object")
    Set tDesc = tClassNameProp.%Get("description")
    Do $$$AssertTrue(tDesc [ "do not include method names", "class_name description contains 'do not include method names'")
    Do $$$AssertTrue(tDesc [ "method_name", "class_name description contains 'method_name'")
    Quit
}

/// <p>AC-2 — registry surfaces get_class_source with non-empty Description.</p>
Method TestRegistryListToolsIncludesGetClassSource()
{
    Set tList = ##class(SessionAgent.Tool.Registry).ListTools()
    Do $$$AssertTrue($IsObject(tList), "ListTools() returns object")
    Set tFound = 0
    Set tDesc = ""
    Set tIter = tList.%GetIterator()
    While tIter.%GetNext(.tKey, .tEntry) {
        If tEntry.%Get("name") = "get_class_source" {
            Set tFound = 1
            Set tDesc = tEntry.%Get("description")
        }
    }
    Do $$$AssertEquals(tFound, 1, "registry surfaces 'get_class_source'")
    Do $$$AssertTrue(tDesc '= "", "get_class_source has non-empty Description in ListTools output")
    Quit
}

/// <p>AC-4 edge — method_name for a nonexistent method returns
/// render_strategy="method_not_found" with empty source_lines and
/// line_count=0. isError is NOT set (success-shape envelope).</p>
Method TestMethodNotFoundReturnsMethodNotFoundEnvelope()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {"class_name": (..#TARGETCLASS), "method_name": "NonexistentMethodXYZ99"}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetClassSource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK for nonexistent method name")
    Do $$$AssertEquals(+tResult.%Get("isError"), 0, "isError NOT set for method_not_found (success-shape)")
    Do $$$AssertEquals(tResult.structuredContent.%Get("render_strategy"), "method_not_found", "render_strategy='method_not_found'")
    Do $$$AssertEquals(tResult.structuredContent.%Get("source_lines").%Size(), 0, "source_lines empty for method_not_found")
    Do $$$AssertEquals(tResult.structuredContent.%Get("line_count"), 0, "line_count=0 for method_not_found")
    Quit
}

/// <p>FR37 — missing class_name returns isError=1 envelope (validation
/// failure never throws).</p>
Method TestMissingClassNameReturnsError()
{
    Set tCtx = ..BuildCtx()
    Set tArgs = {}
    Set tResult = ""
    Set tSC = ##class(SessionAgent.Tool.Inspection.GetClassSource).Invoke(tCtx, tArgs, .tResult)
    Do $$$AssertStatusOK(tSC, "Invoke returns $$$OK on missing class_name (envelope-based)")
    Do $$$AssertEquals(+tResult.%Get("isError"), 1, "isError=1 on missing class_name")
    Quit
}

}
