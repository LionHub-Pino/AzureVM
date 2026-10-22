# AzureGodUltra hardening contract

Target: Lua 5.1 source and the repository's Lua 5.1 runtime tests. Luau and unnamed executors are not certified. Compatibility is established by executable tests, not a universal claim.

Implementation slices:

1. Portable MBA integer-constant pass: bounded 32-bit integer domain, an XOR/AND arithmetic identity expressed with Boolean bit predicates (no external bit library), strict transform budget, preservation of zero signs and noninteger/nonfinite doubles.
2. Deep CFF: bottom-up processing of eligible nested blocks; lower if/elseif/else edges into dispatcher states while preserving branch scopes, condition order, closures, early returns, and loop break ownership. Bounded state count and runtime opaque state predicates. Unsupported blocks stay unchanged.
3. Runtime integrity checks: capability canaries and initialization-time library identity checks; fail closed with a clear error. Do not disable debug hooks, punish filenames, enumerate environments, overwrite host globals, or claim detection of all preinstalled hooks/loggers. Host-controlled memory and debug APIs remain outside the trust boundary.
4. Initialization recovery only: at most two retries, no user code in the protected region. Try xpcall, pcall, then a non-yielding coroutine fallback when those capabilities exist. Payload-integrity failures are terminal. The initializer itself never re-executes a user program or swallows user errors. A separate SafeRetryWrapper can explicitly replay whole payloads as specified below.
5. Enable these features in AzureGodUltra; retain existing defaults for other presets. Test compact output, nested-flow semantics, integer boundaries, injected initialization faults, failed checks, host hooks, nil/false/multiple returns, and user side effects. Run the complete existing gate before pushing main.

Anti-dump and anti-environment-logger limitations: transient buffers are cleared and required runtime functions are captured locally, but live values and initial global lookups remain observable. A host can replace both the runtime and its checks. These measures are not cryptographic authentication, a sandbox, or universal anti-analysis traps.

## Compatibility and behavioral details

- Local identifiers are alpha-renamed before generated code is compiled so hoisting cannot merge repeated local names or accidentally capture global references. Debug-visible local names are not preserved.
- Strict checks compare initialization-time function identities and primitive behavior, not a signature database of executors. They deliberately allow a preinstalled wrapper with correct behavior; this avoids mistaking a profiler or legitimate host adapter for an attack.
- Integrity/capability rejection is an error, never a crash loop, forced termination, host-global mutation, or hook removal. A corrupt payload is never repaired or accepted. The initialization retry layer does not replay integrity failures; the separately configured whole-payload wrapper may revalidate them on each bounded attempt.
- Recovery starts a fresh decoder attempt, discarding partial initialization state. It does not undo side effects inside host-supplied replacement primitives.
- Coroutine fallback rejects yielding initialization; ordinary user-code yields remain supported outside the protected region.
- The full Lua 5.1 quality gate includes all six presets and an additional compact Ultra pass. The separate runtime-matrix script records named installed binary hashes and tests generated output, not full source-language compatibility.


## Explicit whole-payload retry policy

SafeRetryWrapper is a separate optional post-AzureVM pipeline step, now enabled by default in Ultra with three additional retries (four total attempts). This supersedes the previous Ultra default of never replaying user code. It rebuilds the entire decoder/VM factory after any uncaught error, not just registers on a shared prototype.

Only VM-owned state is fresh. External effects, mutable argument objects, host environment changes, and previously escaped closures are not reset. Each original argument tuple is forwarded unchanged by reference. Successful results and final error objects retain nil/false values. RetryCount=0 returns the original generated source with no protected-call wrapper.

The source of an error does not exempt it from outer replay: an integrity failure may be revalidated on each attempt but is never bypassed. Inner initialization recovery remains independently bounded. Payload replay uses xpcall/pcall and therefore inherits Lua 5.1 protected-call yield limitations; it is not a watchdog, crash recovery mechanism, or transaction rollback system.
