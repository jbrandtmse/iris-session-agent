# ObjectScript Testing Framework Knowledge
**Technology Scope: ObjectScript / InterSystems IRIS only.** These rules apply when working on `src/IRISCouch/Test/` ObjectScript test classes. They do NOT apply to Angular/TypeScript frontend testing (Jasmine, Jest, Cypress, Playwright).

## IRIS %UnitTest Framework Core Concepts

### Available Assertion Macros
The %UnitTest.TestCase class provides these STANDARD macros (must use triple dollar signs $$$):
- `$$$AssertEquals(actual, expected, description)` - Assert two values are equal
- `$$$AssertNotEquals(actual, expected, description)` - Assert two values are not equal  
- `$$$AssertTrue(condition, description)` - Assert condition is true
- `$$$AssertStatusOK(status, description)` - Assert status is $$$OK
- `$$$AssertStatusNotOK(status, description)` - Assert status is not $$$OK

### IMPORTANT: Non-existent Macros
These macros DO NOT exist in %UnitTest.TestCase:
- ~~$$$AssertFalse~~ - Use `$$$AssertTrue('condition, description)` instead
- ~~$$$AssertCondition~~ - Use `$$$AssertTrue(condition, description)` instead

### Macro vs Method Distinction
- Assertions in %UnitTest.TestCase are MACROS not methods
- CORRECT: `Do $$$AssertEquals(1, 1, "test")`
- INCORRECT: `Do ..AssertEquals(1, 1, "test")`
- Custom methods can be added to subclasses but they are NOT macros

### Test Class Structure
```objectscript
Class MyPackage.MyTest Extends %UnitTest.TestCase
{
    // Test methods must start with "Test"
    Method TestSomething()
    {
        Do $$$AssertTrue(1=1, "Basic test")
        Quit
    }
    
    // Setup/teardown methods (optional)
    Method OnBeforeOneTest() As %Status { Quit $$$OK }
    Method OnAfterOneTest() As %Status { Quit $$$OK }
}
```

### Test Class Size
- Test class size should be limited to about 500 lines
- When necessary, divide larger test classes into smaller classes to comply with this rule.

### Critical Constructor (%OnNew) Requirements
**CRITICAL**: When extending %UnitTest.TestCase, you MUST properly handle the `initvalue` parameter:

```objectscript
/// Constructor must handle initvalue parameter from parent class
Method %OnNew(initvalue As %String = "") As %Status
{
    // Call parent constructor with initvalue parameter - REQUIRED
    Set tSC = ##super(initvalue)
    If $$$ISERR(tSC) Quit tSC
    
    // Initialize any custom properties here
    Set ..MyProperty = ""
    
    Quit $$$OK
}
```

**Key %OnNew Requirements:**
1. **MUST accept initvalue parameter**: The parent %UnitTest.TestCase requires this
2. **MUST call ##super(initvalue)**: Pass initvalue to parent constructor
3. **NO Private keyword**: ERROR #5477 - %OnNew cannot be Private
4. **Check parent status**: Always check if ##super() succeeded

### MultiDimensional Property Restrictions
**CRITICAL**: MultiDimensional properties CANNOT have datatype specifications:

```objectscript
// INCORRECT - causes compilation error
Property MyData As %String [ MultiDimensional ];

// CORRECT - no datatype for MultiDimensional
Property MyData [ MultiDimensional ];
```

### Common Compilation Issues
1. **Multiline macros**: ObjectScript doesn't support multiline macro calls - keep on single line
2. **Undefined macros**: Using non-existent macros like $$$AssertFalse or $$$AssertCondition
3. **Method vs Macro confusion**: Using ..AssertX() instead of $$$AssertX()
4. **Parameter underscores**: Class parameters cannot contain underscores
5. **Private %OnNew**: ERROR #5477 - Constructor cannot have Private keyword
6. **MultiDimensional datatypes**: Cannot specify datatype for MultiDimensional properties

### Runtime Issues
1. **UNDEFINED errors in %OnNew**: Usually missing initvalue parameter handling
   - Error pattern: `<UNDEFINED> 9 %OnNew+1^%UnitTest.TestCase.1 initvalue`
   - Solution: Implement %OnNew with initvalue parameter
2. **initvalue errors**: Parent class expects initvalue in constructor
3. **Object initialization**: Initialize all properties in %OnNew to avoid UNDEFINED

### Debugging Test Issues
Use debug globals to trace execution:
```objectscript
// In your test or debug method
Set ^ClineDebug = ""
Set ^ClineDebug = ^ClineDebug _ "Step 1 completed; "
// Later retrieve with get_global tool
```

### Best Practices
1. Keep test methods focused and independent
2. Use descriptive assertion messages
3. Clean up test data in OnAfterOneTest
4. Use custom TestCase base class for project-specific assertions
5. Verify compilation before running tests
6. Use test fixtures for common test data
7. Always implement %OnNew properly when extending %UnitTest.TestCase
8. Use debug globals (^ClineDebug) to trace test execution issues

## MCP `iris_execute_tests` Truncation Workaround (Story 4.0 / Epic 3 retro)

**Symptom.** When `mcp__iris-dev-mcp__iris_execute_tests` is invoked with the
**package-runner form** (e.g., `package: "SessionAgent.Test"`) on a package
with many test classes, the **tail entries of the per-class result list are
truncated** in the JSON returned to the agent. The summary `total / pass /
fail` counts the runner reports may be *lower* than the actual count
recorded in the `^UnitTest.Result` global on the IRIS side.

**Recurring incidents.** Stories 2.4 → 2.12 each saw the symptom at least
once during regression sweeps; Story 3.0 saw it on its initial sweep; Story
3.5 confirmed it again on the 161-test Epic 3 baseline. Each story
re-discovered the workaround independently, costing roughly 5 – 10 minutes
of confused investigation per story. This codification ends the
re-explanation cost.

**Workaround — per-class invocation.** Replace the package-runner call with
a sequence of single-class calls and aggregate the sums in the agent /
lead summary:

```
mcp__iris-dev-mcp__iris_execute_tests  test_class: SessionAgent.Test.UtilJsonTest
mcp__iris-dev-mcp__iris_execute_tests  test_class: SessionAgent.Test.UtilRetryWithBackoffTest
…  (repeat per class)
```

The per-class form returns the full result list reliably because each call
fits inside the truncation budget. Aggregate `total / pass / fail` across
calls; the union of all per-class result lists is the ground-truth
regression sweep.

**Verification path — `^UnitTest.Result` global walk.** When in doubt, read
the global directly to confirm the actual recorded counts:

```
mcp__iris-dev-mcp__iris_global_get  global: ^UnitTest.Result
```

The global is shaped `^UnitTest.Result(<runIdx>, <suiteName>, <className>,
<methodName>, …)` — walk the most recent `<runIdx>` (max subscript) to see
every method recorded in this run, regardless of whether the runner JSON
truncated the response. If the global walk shows more entries than the
runner's summary, the runner truncated and the per-class workaround applies.

**When to use which form.**

- **Single-class probe / smoke during dev:** package form is fine —
  truncation only bites at scale.
- **Epic-end full regression sweep (Rule 6 step 3):** ALWAYS per-class.
  Aggregate counts in the retrospective opening so the empirical battery
  evidence is reliable.
- **Cross-suite invariant check** (e.g., "does any class fail under
  audit-ledger writes?"): per-class, scripted, results captured to a file
  the lead reads end-to-end before claiming green.