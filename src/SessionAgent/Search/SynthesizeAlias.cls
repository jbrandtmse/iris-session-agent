/// <p>Story 9.1 Task-0 candidate function — produces a deterministic
/// alias-string for a <code>(tool_name, args)</code> tuple, used by the
/// click-through capture pipeline (Story 9.5) to key the
/// <code>UserVocabulary</code> row that the operator's clicked-result
/// confirmed. Two semantically-equivalent inputs (key-order swapped,
/// key-case mismatched, value-case mismatched, array-reordered, etc.)
/// MUST produce the identical alias string so the same conceptual
/// search "fingerprint" lands on the same vocabulary row.</p>
///
/// <p><b>Normalization rules</b> (per Story 9.1 AC-2):</p>
/// <ol>
/// <li><b>Tool-name prefix:</b> <code>$ZConvert(pToolName, "L")</code>
/// followed by <code>":"</code>. Different tools never collide.</li>
/// <li><b>Key sort:</b> all argument keys lowercased and sorted
/// lexicographically before stringification.</li>
/// <li><b>Key case:</b> <code>$ZConvert(key, "L")</code> applied so
/// <code>{Status:"Error"}</code> and <code>{status:"Error"}</code>
/// produce the same alias.</li>
/// <li><b>Value case (string values):</b> <code>$ZConvert(value, "L")</code>
/// applied to ALL string values for v1. The rougher
/// normalization is acceptable for v1; refinement (categorical-only
/// lowercase, free-text preserved) can come later if false-positive
/// collisions surface.</li>
/// <li><b>Numeric values:</b> stringify via <code>value _ ""</code> so
/// <code>{limit:50}</code> and <code>{limit:"50"}</code> both produce
/// <code>"50"</code> (Story 9.1 AC-2 row 7 — convergence is the chosen
/// design; documented here so Story 9.5 inherits the contract).</li>
/// <li><b>Null values:</b> stringify as the literal string <code>""</code>
/// so they remain DISTINCT from the absence-of-the-key case (Story 9.1
/// AC-2 row 8 — presence-of-key matters).</li>
/// <li><b>Array values:</b> elements stringified per (4)/(5)/(6),
/// THEN sorted lexicographically, THEN joined with <code>","</code> so
/// <code>{status_in:["Error","Suspended"]}</code> and
/// <code>{status_in:["Suspended","Error"]}</code> produce the same alias.</li>
/// <li><b>Nested objects:</b> recursively normalized via
/// <code>NormalizeObject()</code>, then emitted as a brace-bracketed
/// blob so <code>{filters:{a:1,b:2}}</code> and
/// <code>{filters:{b:2,a:1}}</code> produce the same alias.</li>
/// <li><b>Whitespace:</b> NOT collapsed. <code>"foo bar"</code> and
/// <code>"foo  bar"</code> intentionally produce DIFFERENT aliases
/// (Story 9.1 AC-2 row 10 — whitespace is significant).</li>
/// </ol>
///
/// <p><b>Output format:</b>
/// <code>tool_name:k1=v1|k2=v2|...</code> for top-level args. Nested
/// objects emit as <code>{nk1=nv1,nk2=nv2}</code>. Arrays emit as
/// <code>[v1,v2,...]</code> (already-sorted).</p>
///
/// <p><b>Internal vs public.</b> The
/// <code>SynthesizeAlias()</code> ClassMethod is marked
/// <code>[Internal]</code> per Story 9.1 spec — Story 9.5 calls it via
/// fully-qualified <code>##class(SessionAgent.Search.SynthesizeAlias).SynthesizeAlias(...)</code>.
/// Helpers <code>NormalizeObject()</code>, <code>NormalizeArray()</code>,
/// <code>NormalizeValue()</code> are <code>[Internal]</code> as well —
/// they are not part of the public API.</p>
///
/// <p><b>References:</b></p>
/// <ul>
/// <li>Story 9.1 AC-2 — verbatim normalization spec + 10-row determinism table.</li>
/// <li><a href="../../../_bmad-output/planning-artifacts/architecture.md">architecture.md AR12 / AR13-Epic9</a> — click-through capture key contract.</li>
/// <li>Story 9.5 — consumer (RecordClickThrough Zenmethod hyperevent).</li>
/// </ul>
Class SessionAgent.Search.SynthesizeAlias Extends %RegisteredObject
{

/// <p>Public entry point. Returns a deterministic alias string for
/// the <code>(pToolName, pArgs)</code> tuple per the normalization
/// rules in the class header. Empty / <code>$$$NULLOREF</code>
/// <code>pArgs</code> produces <code>tool_name:</code> (the bare
/// tool prefix with no args blob).</p>
ClassMethod SynthesizeAlias(pToolName As %String, pArgs As %DynamicObject) As %String [ Internal ]
{
    Set tToolPart = $ZConvert($Get(pToolName, ""), "L")
    Set tArgsBlob = ""
    If $IsObject($Get(pArgs)) {
        Set tArgsBlob = ..NormalizeObject(pArgs, "|")
    }
    Quit tToolPart _ ":" _ tArgsBlob
}

/// <p>Recursively normalize a <code>%DynamicObject</code> to a
/// deterministic stringified form. Keys lowercased + sorted; values
/// per <code>NormalizeValue()</code>. <code>pSeparator</code> is the
/// between-pairs separator: <code>"|"</code> at the top level,
/// <code>","</code> inside nested braces.</p>
ClassMethod NormalizeObject(pObj As %DynamicObject, pSeparator As %String = ",") As %String [ Internal ]
{
    ; Pass 1: collect (lower-cased-key, original-key, value, type) tuples.
    ; Use %GetIterator() per project rule "%DynamicObject Iterator Safety"
    ; (no %Set / %Remove during iteration).
    Set tIter = pObj.%GetIterator()
    Set tKeysLowered = ""    ; $ListBuild list of lowercased keys (sortable)
    Set tOrigKeyMap = ""     ; PPG-free keyed map: lowercased -> original
    Set tValMap = ""         ; lowercased -> value-string
    While tIter.%GetNext(.tKey, .tVal, .tType) {
        Set tLowered = $ZConvert(tKey, "L")
        Set tKeysLowered = tKeysLowered _ $ListBuild(tLowered)
        Set tValStr = ..NormalizeValue(tVal, tType)
        ; Use a local-array map keyed by the lowercased key. (Process-private
        ; arrays are scoped to this method invocation.)
        Set tNormalized(tLowered) = tValStr
    }

    ; Pass 2: extract sorted unique keys via $ListSort(...) on the lowercased list.
    ; If two keys lowercase to the same string (collision), the second one
    ; in iteration order wins (overwrote the local-array slot in Pass 1).
    Set tSortedKeys = ..SortListBuild(tKeysLowered)

    ; Pass 3: emit "key=value" pairs joined by pSeparator. De-duplicate on
    ; the fly so a key-case collision doesn't double-emit.
    Set tBlob = ""
    Set tPrev = ""
    Set tPtr = 0
    Set tFirst = 1
    While $ListNext(tSortedKeys, tPtr, tK) {
        If (tK = tPrev) Continue   ; skip duplicates from key-case collisions
        Set tPrev = tK
        Set tPair = tK _ "=" _ $Get(tNormalized(tK), "")
        If tFirst {
            Set tBlob = tPair
            Set tFirst = 0
        } Else {
            Set tBlob = tBlob _ pSeparator _ tPair
        }
    }
    Quit tBlob
}

/// <p>Sort a <code>$ListBuild</code> list lexicographically. Returns a
/// new sorted list. Implementation: walk the list into a local array
/// (sorted by ObjectScript subscript collation, which is canonical
/// numeric-then-string lexicographic), then walk the array in $Order
/// to rebuild the sorted list.</p>
ClassMethod SortListBuild(pList As %String) As %String [ Internal ]
{
    Kill tBucket
    Set tPtr = 0
    Set tIdx = 0
    While $ListNext(pList, tPtr, tItem) {
        Set tIdx = tIdx + 1
        ; Subscript by item; nest by tIdx so duplicates don't collide.
        Set tBucket(tItem, tIdx) = ""
    }
    Set tSorted = ""
    Set tKey = ""
    For {
        Set tKey = $Order(tBucket(tKey))
        Quit:tKey=""
        Set tSub = ""
        For {
            Set tSub = $Order(tBucket(tKey, tSub))
            Quit:tSub=""
            Set tSorted = tSorted _ $ListBuild(tKey)
        }
    }
    Quit tSorted
}

/// <p>Normalize a single value. Type comes from
/// <code>%GetIterator</code>'s third arg: <code>"string"</code>,
/// <code>"number"</code>, <code>"boolean"</code>, <code>"null"</code>,
/// <code>"object"</code>, <code>"array"</code>. Returns the
/// stringified normalized form per the class-header rules.</p>
ClassMethod NormalizeValue(pVal, pType As %String) As %String [ Internal ]
{
    If pType = "object" {
        Quit "{" _ ..NormalizeObject(pVal, ",") _ "}"
    }
    If pType = "array" {
        Quit "[" _ ..NormalizeArray(pVal) _ "]"
    }
    If pType = "null" {
        ; AC-2 row 8 — null is distinct from absence; emit empty string
        ; so {status:"Error",source:""} is distinguishable from
        ; {status:"Error"} (key absent → not iterated → not emitted at all).
        Quit ""
    }
    If pType = "boolean" {
        ; "true"/"false" are already lowercase canonical.
        Quit pVal _ ""
    }
    If pType = "number" {
        ; AC-2 row 7 — numeric and string-of-number converge: stringify.
        Quit pVal _ ""
    }
    ; string — lowercase via $ZConvert. Whitespace preserved (AC-2 row 10).
    Quit $ZConvert(pVal _ "", "L")
}

/// <p>Normalize a <code>%DynamicArray</code> — each element via
/// <code>NormalizeValue()</code>, then sort lexicographically, then
/// join with <code>","</code>. Per AC-2 row 4, array reorder must
/// produce the same alias.</p>
ClassMethod NormalizeArray(pArr As %DynamicArray) As %String [ Internal ]
{
    Set tIter = pArr.%GetIterator()
    Set tElems = ""
    While tIter.%GetNext(.tIdx, .tVal, .tType) {
        Set tElems = tElems _ $ListBuild(..NormalizeValue(tVal, tType))
    }
    Set tSorted = ..SortListBuild(tElems)
    ; Join with ","
    Set tOut = ""
    Set tPtr = 0
    Set tFirst = 1
    While $ListNext(tSorted, tPtr, tElem) {
        If tFirst {
            Set tOut = tElem
            Set tFirst = 0
        } Else {
            Set tOut = tOut _ "," _ tElem
        }
    }
    Quit tOut
}

}
