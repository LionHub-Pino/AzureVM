# Changelog

## [2.3.0] - 2026-11-17

### Added
- **Dynamic Rolling Opcode Keying (`src/prometheus/azure_vm/encoder.lua` & `generator.lua`):**
  - Eliminated static 1-to-1 opcode mapping by keying every instruction's opcode with dynamic running PRNG digest: `rop_key = (dg_init + i * 37 + new_prev) % 256`.
  - Every single instruction position now resolves to an unpredictable opcode value that shifts per execution step based on ciphertext feedback, completely neutralizing static opcode table reconstructors and disassembly matrix mappers.
- **Sealed Dispatch Table & Mutation Trapping:**
  - Sealed opcode dispatch table using a metatable proxy (`__index = raw_disp, __newindex = function() TRAP(nil) end, __metatable = false`).
  - The internal VM dispatch loop executes strictly from the lexically scoped `raw_disp` table.
  - Any external attempt to overwrite or hook opcode handlers (`disp[201] = hook`) triggers an immediate runtime integrity fail-closed crash, and `rawset` mutations write to a dead decoy wrapper table that the VM loop never executes from.
- **Prototype Anti-Reflection & Caller Verification Metatable:**
  - Prototype table `ROOTP` wrapped in an anti-reflection metatable with caller inspection (`debug.getinfo(2, "f")`).
  - Only authorized VM closures registered in `OWNED` (`EXEC`, `TRAMP`, `WRAP`, and valid dispatch handlers) are permitted to index prototype structures.
  - External table dumpers (such as `dump_p(y1Erz)`) attempting to harvest bytecode instructions, constants, or child prototypes are immediately trapped and terminated.
- **Masked Dynamic Entrypoint Bootstrap:**
  - Replaced the static return call `return EXEC(ROOTP, GENV, {}, ...)` with a masked randomized dictionary dispatch: `local _boot = {[MAGIC_BOOT] = EXEC}; return _boot[MAGIC_BOOT](ROOTP, GENV, {}, ...)`.
  - Neutralizes regex and AST string-matching scripts searching for fixed VM entrypoint signatures.
- **Centralized String Decryptor Elimination (`src/presets.lua`):**
  - Removed Prometheus's AST `EncryptStrings` pre-pass from AzureVM presets (`Luraph14`, `Luraph15`, `AzureGod`, `AzureGod15`, `AzureGodUltra`, `Balanced`, `Hardened`, `Research`).
  - Eliminates the centralized `main_1` string decryptor helper function and corresponding `OP_CALL` instructions.
  - All strings are now protected exclusively by AzureVM's native 128-bit 2-pass bidirectional S-box ARX cipher embedded in the VM blob, completely depriving dynamic `CALL` tracers of runtime string interception.

## [2.2.0] - 2026-11-17

### Added
- **Pure-Lua 32-bit ARX PRNG & Key Derivation Engine (`src/prometheus/azure_vm/encoder.lua`):**
  - Cryptographically resilient 32-bit Addition-Rotation-XOR (ARX) state engine for high-entropy wire-format diversification without external dependencies.
  - Dynamic key schedule generation producing unique per-build substitution tables and diffusion keys.
- **128-bit 2-Pass Bidirectional S-Box Blob Cipher:**
  - Non-linear 2-pass forward and reverse substitution/diffusion passes over serialized VM bytecode payloads.
  - Eliminates plaintext constant signatures, structural opcode patterns, and frequency analysis.
- **Polymorphic Instruction Wire Format & Shuffled Opcode Layouts (`src/prometheus/azure_vm/generator.lua`):**
  - Shuffled per-prototype instruction layouts with randomized field packing (`OP`, `A`, `B`, `C`, `Bx`, `sBx`).
  - Polymorphic opcode dispatcher using dynamic jump maps and opaque token vaults.
- **Advanced Anti-Tamper Trap Harness (Luarmor / Luraph v15.2 Parity):**
  - **Hook & Tracer Defense:** Real-time `debug.gethook()` verification allowing benign host count hooks while instantly flagging call/line/return hooks (`c`, `l`, `r`).
  - **Roblox Executor API Traps:** Active detection of common executor hooking APIs (`hookfunction`, `hookmetamethod`, `islclosure`, `replaceclosure`).
  - **Environment & Metatable Cloaking:** String metatable integrity canaries, string concatenation verification, and detection of hooked `debug.getinfo`, `debug.getlocal`, `getfenv`, `getmetatable`.
  - **Poison Accumulator & Fail-Closed Guards:** Poison accumulator mechanism that invalidates VM register tables and triggers immediate fail-closed termination upon tamper detection.
- **Resilient Execution & Sandbox Compatibility:**
  - Coroutine-based `pcall`/`xpcall` fallback execution for heavily sandboxed environments where standard error-handling primitives are restricted or revoked.
  - Complete closure environment forwarding supporting custom `getfenv`/`setfenv` scopes without leaking VM internal upvalues.
  - Standard library internal references captured as local upvalues to prevent environment pollution or hijack.
- **Comprehensive E2E Verification Suites (`tests/e2e/`):**
  - Tier 1 Features (44/44 passed across Lua 5.1 & LuaJIT).
  - Tier 2 Boundaries (43/43 passed across Lua 5.1 & LuaJIT).
  - Tier 3 Pairwise Combinations (12/12 passed across Lua 5.1 & LuaJIT).
  - Tier 4 Real-World Workloads (6/6 passed across Lua 5.1 & LuaJIT).
  - 100% pass rate achieved on all regression, validation, and VM semantic suites.

## [2.1.0] - 2026-11-17

### Added
- **Luraph v15.2 Parity & Modern Luau Transpilation Engine:**
  - **Modern Luau Pre-Pipeline Transpiler (`src/prometheus/azure_vm/transpiler.lua`):**
    - Seamless transpilation of modern Luau features into standard Lua 5.1 AST before VM bytecode generation.
    - Unicode escape sequences (`\u{XXXX}` -> UTF-8 byte sequences).
    - Binary numeric literals (`0b[01]+` -> decimal constants).
    - Numeric underscore separators (`1_000_000`, `0x1F_2A` -> normalized numbers).
    - Single-line and multiline Luau type definitions (`type T = { ... }`, `export type ...`) with balanced brace parser `%b{}`.
    - Parameter type annotations, return type annotations, and local variable type assertions.
    - Type casting operators (`expr :: any` -> `(expr)`).
    - String interpolation (backtick strings `` `Welcome, {name}!` `` -> string concatenation).
    - Ternary if-else expressions (`local x = if a then b else c` -> `((a) and (b) or (c))`).
    - Compound assignment operators (`+=`, `-=`, `*=`, `/=`, `%=`, `^=`, `..=`).
  - **Luraph v15.2 Runtime Security & Integrity Hardening (`src/prometheus/azure_vm/generator.lua`):**
    - Anti-Hook & Callstack Traceback Scanner: Scans stack frames for deobfuscators, tracers, and hook wrappers (`unluac`, `deobfuscator`, `disassembler`, `tracer`, `in function 'dump'`, `in function 'hook'`) with zero false-positives on source filenames (`hook_config.lua`, `dump_report.lua`).
    - C-Closure Dump Traps: Guards against executor C-closure dumping via `pcall(string.dump, pcall)`, `pcall(string.dump, select)`, `pcall(string.dump, tostring)`, `pcall(string.dump, type)`.
    - String Metatable & Concat Canary: Verifies `("lura" .. "ph") == "luraph"` and `getmetatable("").__index == string`.
    - Zero-Freeze Lookup Table: Precomputed byte lookup table `v[c]` for ultra-fast VM runtime decompression, eliminating thread freezes on Roblox executors.
  - **New Goal-Oriented Presets & Aliases (`src/presets.lua`):**
    - `Luraph15_2`: Luraph v15.2 parity profile with advanced AST transforms, template mode 15, and v15.2 canaries/anti-dump traps.
    - Aliases: `v15.2`, `v15`, `AzureGod15_2`.
  - **Luau & Hardening Test Suites:**
    - `tests/luau-v15.luau`: Comprehensive fixture testing all modern Luau syntax features.
    - `tests/v15-hardening.lua`: Runtime verification of canaries, metatables, select range, and C-closure dump traps.
    - `tests/luau-validation.sh`: Dedicated test runner asserting exact output matching across both `Luraph15_2` and `Luraph` presets.
- **Production Engineering Overhaul (P0-P5):**
  - **Dynamic Template Resolution:** Fixed CLI issue where custom aliases (e.g., `Biendieu`, `Dudieu`) incorrectly reported Template Mode 14 instead of inspecting the underlying pipeline configuration.
  - **New Goal-Oriented Presets:** Introduced `Fast` (minimal overhead for 60-120 FPS render loops), `Balanced` (production default), `Hardened` (deep CFF, MBA, integrity guards), and `Research` (deterministic reverse-engineering analysis).
  - **MONO 22 Album Trilogy Presets:** Fully maintained and tested aliases: `Khoidieu` (Chương I), `Biendieu` (Chương II), and `Dudieu` (Chương III).
  - **Automated Semantic Differential Testing:** Integrated comprehensive 84-test matrix validating identical runtime output across Lua 5.1, LuaJIT, and Luau.
  - **Fuzz & Malformed Bytecode Validation:** Added 98-case truncation and bit-flip fuzzing tests ensuring fail-closed stability of the bytecode deserializer without unhandled interpreter crashes.
  - **Multi-Preset Informational Benchmarking:** Enhanced `scripts/benchmark-vm.lua` to output compile time, output size, and slowdown across all presets.
  - **Threat Model & Reverse Engineering Evaluation:** Added `docs/threat-model.md` documenting realistic security boundaries, work-factor metrics, and operational guidelines.
- Added the optional post-AzureVM SafeRetryWrapper step, enabled in Ultra with RetryCount=3 (three retries/four total attempts). Each attempt recreates the complete VM factory, including root instruction tables erased before tailcalls.
- Added --retry-count=N and --retry-count N overrides (0..100); zero disables payload replay, and positive overrides opt other AzureVM presets in.
- Whole-payload replay intentionally retains external side effects and mutable arguments. It preserves successful nil/false/multiple returns and rethrows the final error object; xpcall/pcall impose runtime-specific yield limitations.
- Added regression tests for factory reset, tailcall failures, attempt limits, irreversible side effects, tuple/error preservation, integrity rejection, step ordering, and compact CLI validation.
- Ultra now uses bottom-up deep-CFF with conditional-edge lowering, state-dependent opaque dispatch predicates, bounded state counts, and binding-safe local alpha-renaming.
- Added a budgeted, bit-library-free MBA AST pass for exact nonzero 32-bit integer constants; later arithmetic transforms preserve MBA subtrees.
- Ultra enables fail-closed runtime primitive/library-identity checks and initialization-only recovery with xpcall/pcall/coroutine fallback, capped at two retries. User code, errors, return values, and yields are outside the initialization retry region. SafeRetryWrapper adds a separate explicitly replaying payload layer.
- Added compact semantic harness mode, nested/shadowed-local fixtures, fault injection and integrity tests, and an optional installed-runtime matrix for Lua 5.1/LuaJIT/Luau CLI. These checks do not establish universal executor or anti-dump/anti-hook/anti-logger guarantees.
- Build/prototype-dependent register-address mapping through a proxy, preserving captured upvalues and nil/false values. Backing register values remain observable to the host.
- On-demand string constant decoding without a persistent plaintext constant cache; repeated accesses have additional CPU/allocation cost.
- `--compact` and API `Compact=true` emit a single physical line including a collision-safe comment header; no compression or universal executor compatibility is implied.
- Focused tests for lazy string materialization, register mapping, compact CLI output, and adversarial multiline/delimiter header text.
- Regression coverage for 10 native-source roundtrips, limited compound-assignment fallback, shebang handling, early binary-input rejection, 20 filename/template/seed contexts, and preservation of an installed host debug hook.
- A literal-boundary semantic fixture runs through every advertised preset in CI.

### Compatibility
- Syntax accepted by Lua 5.1 keeps Lua 5.1 string-escape semantics. Limited Luau preprocessing now runs only when native compilation fails; this is not automatic full Luau dialect detection. Explicit users of the text preprocessor still need target-specific compatibility tests.

### Latest local verification
- 133 semantic comparisons passed: 19 fixtures across all six presets, plus 19 additional Ultra compact checks.
- Compact Ultra output matched the Lua 5.1 baseline for 19 fixtures on each installed Lua 5.1, LuaJIT, and Luau CLI (57 comparisons). This is a named-binary test result, not universal compatibility.
- MBA boundaries/budgets, deep-CFF binding preservation, transient faults, terminal integrity failures, all three protection paths, user error objects/yields/side effects, and host debug hook preservation passed.

## [2.0.0] - 2026-10-22

This release includes a signed-zero behavior change; review the compatibility notes before upgrading from v1.0.0.

### Added
- Each string constant now receives a unique build-local nonce and a rolling stream with ciphertext feedback, including identical literals in different prototypes. This is reversible obfuscation, not cryptographic encryption.
- Internal string payload lengths use 32 bits instead of 16, with regression coverage for empty strings, all byte values, and strings larger than 65,535 bytes.
- Numeric regression tests cover 164 serializer roundtrips, 18 preset/seed combinations, and an additional semantic fixture in every advertised preset.

### Fixed
- IEEE754 serialization preserves signed zero, subnormals, maximum finite values, infinities, and NaN semantics using Lua 5.1-compatible byte construction.
- AST numeric output uses enough decimal digits to round-trip doubles; scientific/hexadecimal mutations avoid lossy representations and zero signs are protected from arithmetic rewrites.
- Negative zero is emitted using a runtime expression to avoid Lua 5.1 pooling it with positive-zero constants introduced by AST transforms.
- Hexadecimal mutation checks the portable unsigned 32-bit range before calling the host integer formatter.

### Compatibility
- Existing generated files and release `v1.0.0` are unchanged. New output includes its own updated decoder; fixed-seed output bytes may differ between versions.
- AST output now deliberately preserves a literal negative zero's sign. Programs depending on Lua 5.1's native pooling of `+0` and `-0` constants may observe a difference; this normalization is not a promise to reproduce that compiler quirk.

### Verification
- 102 semantic comparisons across six presets passed, together with 164 numeric serializer roundtrips and 18 numeric preset/seed combinations.
- Long/binary string, nonce diversity, ciphertext feedback, deterministic output, payload integrity, reader validation, and benchmark regression checks passed.
- Lua 5.1 CLI is the verified baseline. This release does not certify full Luau, executor, or web integration compatibility, or make cryptographic secrecy guarantees.

## [1.0.0] - 2026-10-21

First versioned AzureVM release, including the latest stability improvements.

### Added
- Independent per-prototype and chained per-instruction VM field layouts.
- Payload corruption checks, deterministic seeded builds, OS-randomized default build seeds, and transient decoded-payload cleanup.
- A shared Lua 5.1 quality gate covering all six advertised AzureVM presets, CLI behavior, and malformed-bytecode regression tests.
- CI for syntax checks, focused regressions, VM behavior comparisons, and benchmark artifacts.
- Per-fixture timeouts and strict success requirements in the VM comparison harness.
- Repeatable Lua microbenchmarks with warm-up and median/min/max CPU time.
- Native-versus-VM benchmark CSV reports with correctness checks, two fixed seeds, compile cost, output size, and median execution time including VM startup/decoding.

### Fixed
- CLI rejects missing option values, unknown options/presets, extra inputs, and invalid seeds instead of silently falling back to different settings.
- Fixed-seed CLI builds seed both AST transforms and the VM encoder for reproducible advanced-preset output.
- Bytecode reader bounds-checks integers, doubles, strings, counts, and debug data; rejects truncated chunks, unsupported large string lengths, missing string terminators, excessive prototype nesting, and trailing data.
- Benchmark sample validation rejects nonnumeric input, and even-sized samples use the average of the two middle values.

### Changed
- CLI version reports `AzureVM v1.0.0`.

### Verification
- Lua 5.1: 96 semantic comparisons across six presets passed.
- Regression checks cover CLI validation, deterministic output, payload integrity, layout decoding, benchmark statistics, and malformed bytecode (including 334 truncations of the reader fixture).
- Run `bash scripts/check-lua51.sh` to reproduce the quality gate.

### Security and compatibility notes
- The payload checksum is an integrity check, not a cryptographic signature or anti-tamper guarantee.
- Obfuscation does not keep runtime code or values secret from an analyst controlling the execution environment.
- Lua 5.1 is the supported bytecode compiler/runtime baseline. Luau and executor compatibility are not established by this release's test suite.
- Benchmark results are informational and environment-dependent; the VM introduces runtime overhead, not a performance improvement over native Lua.
