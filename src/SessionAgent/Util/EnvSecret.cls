/// <p>Resolves SessionAgent LLM provider API keys via the documented
/// three-rung credential ladder, without ever logging or persisting the
/// resolved key value (FR40, NFR-S2, NFR-S3).</p>
///
/// <p><b>Resolution ladder</b> (first non-empty wins):</p>
/// <ol>
/// <li><b>Process environment variable</b> via
/// <code>$SYSTEM.Util.GetEnviron(pEnvVarName)</code> when
/// <code>pEnvVarName '= ""</code>. Containerized deployments favor this
/// path (12-factor configuration).</li>
/// <li><b><code>Ens.Config.Credentials</code> row</b> opened lock-free via
/// <code>%OpenId(pCredentialName, 0)</code> when
/// <code>pCredentialName '= ""</code> and the row exists. Concurrency=0
/// avoids serializing every LLM call on a credentials lock; rare operator
/// edits are picked up on the next call. Any failure inside the open or
/// the <code>.Password</code> getter falls through to the next rung — the
/// exception is swallowed so the caller never sees an
/// <code>Ens.Config.Credentials</code> internal error escape from
/// <code>Resolve</code>.</li>
/// <li><b>AES-encrypted custom store</b> (stub). v1 ships the interface
/// only; <code>ResolveFromAesStore</code> returns <code>""</code>.
/// Operators choosing the AES route opt in by extending this class. Full
/// implementation deferred per architecture line 255 ("custom
/// AES-encrypted store; never in <code>Config.Agent</code> row").</li>
/// </ol>
///
/// <p>If no rung resolves, <code>Resolve</code> returns <code>""</code>.
/// The caller is responsible for surfacing this as a structured error;
/// <code>Resolve</code> never throws.</p>
///
/// <p><b>NEVER-LOG INVARIANT (NFR-S3)</b>. The implementation MUST NOT
/// call <code>Write</code> on, append to <code>^ClineDebug</code> or any
/// other persistent global, concatenate into a logger / status / error
/// message, or otherwise embed the resolved key value anywhere outside
/// the direct return value of <code>Resolve</code>. Reviewer enforcement
/// + <code>SessionAgent.Test.EnvSecretTest.TestResolveDoesNotMutateClineDebug</code>
/// close the empirical loop for the surfaces visible at this story; full
/// audit-row coverage lands in Stories 2.5/2.9.</p>
///
/// <p><b>References</b>:</p>
/// <ul>
/// <li><a href="../planning-artifacts/epics.md">epics.md Story 2.3</a>
/// (lines 772-796) — AC source.</li>
/// <li><a href="../planning-artifacts/architecture.md">architecture.md</a>
/// §"Credential storage" (line 255), file path (line 864).</li>
/// <li><a href="../planning-artifacts/prd.md">prd.md</a> FR40 (line 556),
/// NFR-S2 (line 602), NFR-S3 (line 603).</li>
/// <li><a href="../../irislib/Ens/Config/Credentials.cls">irislib/Ens/Config/Credentials.cls</a>
/// — <code>SystemName</code> is the IdKey (line 64);
/// <code>Password</code> is <code>%CSP.Util.Passwd</code> with a custom
/// <code>PasswordGet</code> that fetches from
/// <code>%SYS.Ensemble.SecondaryGet</code> (lines 18, 28-38).</li>
/// </ul>
Class SessionAgent.Util.EnvSecret Extends %RegisteredObject
{

/// <p>Resolve the API key for the given env-var / credential pair via the
/// three-rung ladder documented on the class. Returns the resolved key,
/// or <code>""</code> if no rung resolves.</p>
///
/// <p>Both arguments default to <code>""</code>; passing both empty is
/// legal and returns <code>""</code> (the test
/// <code>TestEmptyArgsReturnEmpty</code> locks this).</p>
///
/// <p>Returns <code>%String</code> directly (not <code>%Status</code>):
/// the caller wants the value, not a status code, and the never-log
/// invariant means we never want to embed the value into a status
/// message either.</p>
ClassMethod Resolve(pEnvVarName As %String = "", pCredentialName As %String = "") As %String
{
    ; Rung 1: process environment variable.
    If pEnvVarName '= "" {
        Set tEnvValue = $SYSTEM.Util.GetEnviron(pEnvVarName)
        If tEnvValue '= "" {
            Quit tEnvValue
        }
    }

    ; Rung 2: Ens.Config.Credentials row.
    ;
    ; Concurrency=0: lock-free read. Any failure inside the open or the
    ; .Password getter falls through to rung 3 — we explicitly swallow
    ; the exception so a transient credentials issue doesn't propagate
    ; out of the resolver. Argumentless Quit inside Try/Catch per
    ; project rule §"QUIT Statement Restrictions".
    If pCredentialName '= "" {
        Set tCredValue = ""
        Try {
            If ##class(Ens.Config.Credentials).%ExistsId(pCredentialName) = 1 {
                Set tCred = ##class(Ens.Config.Credentials).%OpenId(pCredentialName, 0)
                If $IsObject(tCred) {
                    Set tCredValue = tCred.Password
                }
            }
        }
        Catch ex {
            ; Swallow — fall through to rung 3. Do NOT embed any
            ; credential-name or value content into any log surface.
            Set tCredValue = ""
        }
        If tCredValue '= "" {
            Quit tCredValue
        }
    }

    ; Rung 3: AES-encrypted custom store (v1 stub returns "").
    Quit ..ResolveFromAesStore(pCredentialName)
}

/// <p>Predicate: returns 1 if <method>Resolve</method> would return a
/// non-empty value for the given pair, 0 otherwise. Provided so callers
/// (e.g., <code>Installer.Install</code> deciding whether to enable an
/// agent) can probe without copying the key value into a local variable
/// they then have to be careful about.</p>
///
/// <p><b>Implementation note:</b> internally calls <code>Resolve</code>
/// and compares to <code>""</code>. Yes, the value is materialized
/// briefly inside the ClassMethod stack frame, but it never escapes
/// (the return is <code>%Boolean</code>). The alternative — a
/// separately-implemented predicate that walks the ladder again —
/// would duplicate the resolution logic and create a drift risk.</p>
ClassMethod IsResolvable(pEnvVarName As %String = "", pCredentialName As %String = "") As %Boolean
{
    Quit (..Resolve(pEnvVarName, pCredentialName) '= "")
}

/// <p>v1 stub for the AES-encrypted custom store rung. Returns
/// <code>""</code> unconditionally. Operators who want to ship an
/// AES-backed key store opt in by subclassing
/// <class>SessionAgent.Util.EnvSecret</class> and overriding this
/// method; the rest of the resolver is unchanged.</p>
///
/// <p>Full implementation deferred per architecture.md line 255
/// ("custom AES-encrypted store; never in <code>Config.Agent</code> row").
/// The deferral lives at the rung level (not the class level) so the
/// ladder shape stays stable when the AES backend lands later.</p>
ClassMethod ResolveFromAesStore(pCredentialName As %String = "") As %String [ Private ]
{
    Quit ""
}

}
