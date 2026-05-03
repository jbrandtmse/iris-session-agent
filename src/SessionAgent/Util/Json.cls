/// <p>Foundational JSON helper class for <code>SessionAgent.*</code> code that
/// manipulates <code>%DynamicObject</code> / <code>%DynamicArray</code> values.
/// Encapsulates the recurring patterns called out by project rules so callers
/// don't reimplement them per-class.</p>
///
/// <p>Methods:</p>
/// <ul>
/// <li><code>EmitNull(obj, key)</code> — write JSON literal <code>null</code>
/// to a key (NOT the string <code>"null"</code>) per project rule
/// §"<code>%DynamicObject</code> null emission".</li>
/// <li><code>Redact(obj, keyList, .out)</code> — deep-clone an object and
/// replace every property whose key matches a name in <code>keyList</code>
/// with the literal string <code>"&lt;redacted&gt;"</code>; recurses into
/// nested objects and arrays. Used by audit-log writers (NFR-S3).</li>
/// <li><code>DeepMerge(base, overlay, .out)</code> — recursive merge with
/// overlay-wins semantics; overlay <code>null</code> overrides base value;
/// overlay scalar overrides base object; overlay array <b>replaces</b> base
/// array (no concatenation).</li>
/// <li><code>IsObject(value)</code> — predicate for
/// <code>%Library.DynamicObject</code>.</li>
/// <li><code>IsArray(value)</code> — predicate for
/// <code>%Library.DynamicArray</code>.</li>
/// </ul>
///
/// <p>References: project rules in
/// <code>.claude/rules/iris-objectscript-basics.md</code> §"<code>%DynamicObject</code>
/// null emission", §"<code>%DynamicObject</code> Iterator Safety",
/// §"<code>%Status</code> return convention", §"QUIT Statement Restrictions
/// in Try/Catch Blocks".</p>
Class SessionAgent.Util.Json Extends %RegisteredObject
{

/// <p>Set <code>pKey</code> on <code>pObj</code> to JSON literal
/// <code>null</code>. The third parameter to <code>%Set</code> is the type
/// hint, not the value: <code>%Set(key, "", "null")</code> emits
/// <code>"key":null</code>. The mistake of writing <code>%Set(key, "null", "null")</code>
/// would emit <code>"key":"null"</code> (a string), which is wrong.</p>
///
/// <p>Returns <code>%Status</code> per project rule.</p>
ClassMethod EmitNull(pObj As %DynamicObject, pKey As %String) As %Status
{
    Set tSC = $$$OK
    Try {
        Do pObj.%Set(pKey, "", "null")
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>Produce a deep-cloned <code>%DynamicObject</code> in <code>pOut</code>
/// where every property whose key matches a name in <code>pKeyList</code>
/// (a comma-delimited list, e.g. <code>"api_key,Authorization,password"</code>)
/// is replaced with the literal string <code>"&lt;redacted&gt;"</code>.
/// Recursion descends into nested <code>%DynamicObject</code> and
/// <code>%DynamicArray</code> values.</p>
///
/// <p><b>Implementation choice:</b> deep-clone via JSON round-trip
/// (<code>%FromJSON(pObj.%ToJSON())</code>), then walk the clone in place.
/// This sidesteps the iterator-safety constraint entirely — the source
/// object is never mutated and we never call <code>%Set</code>/<code>%Remove</code>
/// while iterating the source. The cost is one full JSON serialize+parse,
/// acceptable for the audit-log redaction call site (executed once per LLM
/// call, not in a hot loop). The alternative collect-keys-then-modify
/// pattern is also safe but more code; we prefer the simpler form here per
/// the Dev Notes hint in the story spec.</p>
///
/// <p>The walk uses a recursive helper <code>RedactWalkObject</code> /
/// <code>RedactWalkArray</code>. Within the walk on the clone, we iterate
/// keys via <code>%GetIterator</code> and apply <code>%Set</code> to the
/// SAME object — the iterator-safety rule is about not mutating an object
/// while iterating it. We do not use <code>%Set</code> to add or remove
/// keys; we only overwrite values for existing keys, which is safe in
/// practice across all IRIS versions, but to be maximally defensive we
/// also collect the keys-to-redact into a list during iteration and apply
/// the overwrites in a second pass.</p>
ClassMethod Redact(pObj As %DynamicObject, pKeyList As %String, ByRef pOut As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pOut = ""
    Try {
        ; Build a hash-like dynamic object of the redaction key set so the
        ; walk can do an O(1) %IsDefined-style lookup per key.
        Set tKeys = ##class(%DynamicObject).%New()
        Set tCount = $Length(pKeyList, ",")
        For i = 1:1:tCount {
            Set tName = $Piece(pKeyList, ",", i)
            If tName '= "" {
                Do tKeys.%Set(tName, 1)
            }
        }

        ; Deep clone via JSON round-trip — sidesteps iterator-safety on
        ; source object completely (we never touch pObj after this point).
        Set pOut = ##class(%DynamicObject).%FromJSON(pObj.%ToJSON())

        ; Walk the clone and redact in place.
        Do ..RedactWalkObject(pOut, tKeys)
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>Internal recursive helper. Walks <code>pObj</code> (a
/// <code>%DynamicObject</code>) and replaces any property whose key is
/// present in <code>pKeys</code> with the literal string
/// <code>"&lt;redacted&gt;"</code>. Recurses into nested objects/arrays.</p>
///
/// <p>Iterator safety: keys to overwrite are collected during iteration
/// into a <code>$ListBuild</code> list, then overwrites are applied in a
/// second pass (per project rule §"<code>%DynamicObject</code> Iterator
/// Safety"). Recursion into nested structures happens in a separate pass
/// after the iterator is closed.</p>
ClassMethod RedactWalkObject(pObj As %DynamicObject, pKeys As %DynamicObject) [ Private ]
{
    ; Pass 1: discover keys to redact AND keys whose values are nested
    ; structures we must recurse into. We don't mutate during iteration.
    Set tToRedact = ""
    Set tNested = ""
    Set tIter = pObj.%GetIterator()
    While tIter.%GetNext(.tKey, .tVal, .tType) {
        If pKeys.%IsDefined(tKey) {
            Set tToRedact = tToRedact _ $ListBuild(tKey)
        } ElseIf (tType = "object") || (tType = "array") {
            Set tNested = tNested _ $ListBuild(tKey)
        }
    }

    ; Pass 2: apply redactions on the keys collected above.
    Set tPtr = 0
    While $ListNext(tToRedact, tPtr, tKey) {
        Do pObj.%Set(tKey, "<redacted>")
    }

    ; Pass 3: recurse into nested structures (skip keys we just redacted —
    ; they are now scalar strings). Use the public IsObject / IsArray
    ; predicates for type detection so the foundational helpers and the
    ; internal walk stay consistent.
    Set tPtr = 0
    While $ListNext(tNested, tPtr, tKey) {
        Set tChild = pObj.%Get(tKey)
        If ..IsObject(tChild) {
            Do ..RedactWalkObject(tChild, pKeys)
        } ElseIf ..IsArray(tChild) {
            Do ..RedactWalkArray(tChild, pKeys)
        }
    }
    Quit
}

/// <p>Internal recursive helper. Walks each element of a
/// <code>%DynamicArray</code> and recurses into nested objects/arrays.
/// Array elements themselves are not subject to key-based redaction
/// (the keys live one level up, in the parent object); we only descend.</p>
ClassMethod RedactWalkArray(pArr As %DynamicArray, pKeys As %DynamicObject) [ Private ]
{
    Set tIter = pArr.%GetIterator()
    Set tNested = ""
    While tIter.%GetNext(.tIdx, .tVal, .tType) {
        If (tType = "object") || (tType = "array") {
            Set tNested = tNested _ $ListBuild(tIdx)
        }
    }
    Set tPtr = 0
    While $ListNext(tNested, tPtr, tIdx) {
        Set tChild = pArr.%Get(tIdx)
        If ..IsObject(tChild) {
            Do ..RedactWalkObject(tChild, pKeys)
        } ElseIf ..IsArray(tChild) {
            Do ..RedactWalkArray(tChild, pKeys)
        }
    }
    Quit
}

/// <p>Return a new <code>%DynamicObject</code> in <code>pOut</code>
/// combining <code>pBase</code> and <code>pOverlay</code> with overlay
/// keys winning at any depth. Type-mismatch rules:</p>
/// <ul>
/// <li>Overlay JSON <code>null</code> overrides base value (whatever its
/// type) — emitted via <code>EmitNull</code> on the result.</li>
/// <li>Overlay scalar overrides base object.</li>
/// <li>Overlay array <b>replaces</b> base array (does NOT concatenate).</li>
/// <li>Both base and overlay objects at the same key — recurse and merge.</li>
/// </ul>
///
/// <p>Implementation: start with a deep clone of <code>pBase</code> via
/// JSON round-trip, then walk overlay's keys and apply the rules above.
/// The clone ensures the base argument is never mutated.</p>
ClassMethod DeepMerge(pBase As %DynamicObject, pOverlay As %DynamicObject, ByRef pOut As %DynamicObject) As %Status
{
    Set tSC = $$$OK
    Set pOut = ""
    Try {
        ; Deep clone of pBase becomes the result; we never touch pBase
        ; afterward.
        Set pOut = ##class(%DynamicObject).%FromJSON(pBase.%ToJSON())
        Do ..MergeWalkObject(pOut, pOverlay)
    }
    Catch ex {
        Set tSC = ex.AsStatus()
    }
    Quit tSC
}

/// <p>Internal recursive helper. Applies overlay keys to dest in place.
/// Both arguments must be <code>%DynamicObject</code> (not arrays — array
/// merging is governed by the caller via "overlay array replaces base"
/// semantics, applied at the parent-object level).</p>
ClassMethod MergeWalkObject(pDest As %DynamicObject, pOverlay As %DynamicObject) [ Private ]
{
    ; Collect overlay keys via iterator (we never mutate pOverlay; this
    ; first pass is purely for capture). Re-fetch values from pOverlay in
    ; the second pass — safe because pOverlay is untouched.
    Set tKeys = ""
    Set tIter = pOverlay.%GetIterator()
    While tIter.%GetNext(.tKey, .tVal, .tType) {
        Set tKeys = tKeys _ $ListBuild(tKey)
    }

    Set tPtr = 0
    While $ListNext(tKeys, tPtr, tKey) {
        Set tOverlayVal = pOverlay.%Get(tKey)
        Set tOverlayType = pOverlay.%GetTypeOf(tKey)

        If tOverlayType = "null" {
            ; Overlay null overrides base value — emit JSON null on dest.
            Do pDest.%Set(tKey, "", "null")
        } ElseIf tOverlayType = "object" {
            ; Overlay is object. If dest has a corresponding object,
            ; recurse; otherwise replace with a deep-clone of the overlay
            ; object (so future mutations don't leak back into pOverlay).
            If pDest.%IsDefined(tKey) && (pDest.%GetTypeOf(tKey) = "object") {
                Do ..MergeWalkObject(pDest.%Get(tKey), tOverlayVal)
            } Else {
                Do pDest.%Set(tKey, ##class(%DynamicObject).%FromJSON(tOverlayVal.%ToJSON()))
            }
        } ElseIf tOverlayType = "array" {
            ; Overlay array REPLACES base array (no concatenation).
            ; Deep-clone the overlay array so mutations don't leak.
            Do pDest.%Set(tKey, ##class(%DynamicArray).%FromJSON(tOverlayVal.%ToJSON()))
        } Else {
            ; Scalar (string, number, boolean) — overlay wins.
            Do pDest.%Set(tKey, tOverlayVal, tOverlayType)
        }
    }
    Quit
}

/// <p>Predicate: returns 1 if <code>pValue</code> is a
/// <code>%Library.DynamicObject</code>, 0 otherwise. Pure-functional
/// helper; returns <code>%Boolean</code> directly (no <code>%Status</code>).</p>
ClassMethod IsObject(pValue) As %Boolean
{
    If '$IsObject(pValue) Quit 0
    Quit (pValue.%ClassName(1) = "%Library.DynamicObject")
}

/// <p>Predicate: returns 1 if <code>pValue</code> is a
/// <code>%Library.DynamicArray</code>, 0 otherwise. Pure-functional
/// helper; returns <code>%Boolean</code> directly (no <code>%Status</code>).</p>
ClassMethod IsArray(pValue) As %Boolean
{
    If '$IsObject(pValue) Quit 0
    Quit (pValue.%ClassName(1) = "%Library.DynamicArray")
}

}
