# Azure VM (AzureObf)

<div align="center">

```text
       ___                             ____  __      ____  
      /   | ____  __  __________      / __ \/ /_    / __/  
     / /| |/_  / / / / / ___/ _ \    / / / / __ \  / /_    
    / ___ | / /_/ /_/ / /  /  __/   / /_/ / /_/ / / __/    
   /_/  |_|/___/\__,_/_/   \___/    \____/_.___(_)_/       
```

### Lua 5.1 VM-based obfuscator
*Custom opcode mapping • rolling instruction encoding • optional AST transforms*

[![GitHub Stars](https://img.shields.io/github/stars/LionHub-Pino/AzureVM?style=flat-square&color=yellow)](https://github.com/LionHub-Pino/AzureVM/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/LionHub-Pino/AzureVM?style=flat-square&color=blue)](https://github.com/LionHub-Pino/AzureVM/network/members)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=flat-square)](LICENSE)
[![Lua 5.1](https://img.shields.io/badge/Lua-5.1-blue.svg?style=flat-square)](https://www.lua.org/)
[![Luau](https://img.shields.io/badge/Luau-Partial%20transpilation-yellow.svg?style=flat-square)](https://luau-lang.org/)
[![Base Library: Prometheus](https://img.shields.io/badge/Base%20Library-Prometheus-blueviolet.svg?style=flat-square)](https://github.com/prometheus-lua/Prometheus)

</div>

---

## 📌 Attribution & Credits

> [!IMPORTANT]
> **Base Library Notice:**  
> **Azure VM** is built on top of the open-source pipeline of **[Prometheus Lua Obfuscator](https://github.com/prometheus-lua/Prometheus)** created by **levno-710**.
>
> - **Prometheus Core:** Powers our foundational parsing, lexing, Abstract Syntax Tree (AST) manipulation, scope resolution, and AST unparsing infrastructure.
> - **Azure VM Additions:** Developed by **Azure**, adding a Lua 5.1 bytecode reader, custom instruction encoder and VM runtime, per-prototype field layouts, and optional AST transformation steps.

---

## ✨ Overview

**Azure VM** reads Lua 5.1 bytecode and emits a Lua-based interpreter with an encoded instruction payload. It also has a limited text preprocessor for some Luau syntax. Full Luau compatibility and Roblox executor compatibility have **not** been established by the repository's tests.

The compiler API tries native Lua 5.1 first, without rewriting string literals or line breaks. Limited Luau preprocessing is attempted only if native compilation fails; code valid in both dialects keeps Lua 5.1 semantics. Source/options types are validated and binary chunk input is rejected before the native loader. Compilation is not a sandbox or a resource limit.

Obfuscation can increase reverse-engineering effort, but it does not make code secret once it runs on a machine controlled by an analyst. The output contains the VM and its decoder; live values can be inspected or dumped. No claim of resistance to a particular deobfuscator is made without a reproducible test.

Preset names containing **`Luraph`** are historical compatibility names for AzureVM configurations. This project is not Luraph, is not affiliated with Luraph, and has not been shown to match or exceed Luraph v15.

---

## 🌟 Key Architecture & Features

### 1. Runtime and memory
- Uses a byte lookup table during payload decoding.
- Logical VM registers use a proxy over build/prototype-dependent affine storage addresses; captured upvalues continue to reference the same proxy. The backing values are not encrypted and remain inspectable by a host controlling the runtime.
- String constants remain encoded until accessed and are decoded on each access without a persistent plaintext constant cache. Active values and host-managed string allocations remain observable; this is not secure memory erasure. Repeated access trades CPU and allocations for less eager plaintext materialization.
- Clears the transient decoded payload buffer after materializing prototypes. Live VM state remains in memory while needed.
- Load time, runtime overhead, memory use, and executor timeout behavior depend on the script and environment; no universal bounds are claimed.

### 2. 🔀 Polymorphic Virtual ISA & Dynamic Encryption
- **Seeded opcode mapping:** The build seed controls a shuffled opcode map. Fixed seeds produce reproducible output.
- **Rolling instruction encoding:** Each encoded instruction contributes to the key used for the next instruction. The decoder and key material are included in the generated file.
- **Chained field layouts:** Nested functions have different base layouts, and each instruction's field arrangement also depends on the previous encoded instruction.
- **Per-string stream diversity:** Each string constant gets a unique build-local nonce and ciphertext feedback, so identical literals need not have identical encoded bytes. This is reversible obfuscation, not cryptographic encryption; plaintext values still exist after decoding.

### 3. 🛡️ Advanced AST Mutation Pipeline
- **Deep Control Flow Flattening (CFF):** `AzureGodUltra` processes eligible blocks bottom-up, lowers conditional edges into bounded dispatchers, preserves resolved local bindings through alpha-renaming, and uses state-dependent opaque predicates. Blocks with escaping breaks/continues or excessive state counts stay unchanged.
- **Opaque Predicates:** Available in the `AzureGodUltra` preset.
- **String transforms:** `SplitStrings` and `EncryptStrings` are enabled in the non-default advanced presets.
- **Numbers to Expressions:** Enabled in the non-default advanced presets.
- **MBA constants:** `AzureGodUltra` adds portable Boolean–Arithmetic identities for exact nonzero 32-bit integer constants. Fractional, nonfinite, out-of-range, and signed-zero values are not rewritten by MBA. Transform budgets bound code growth.

### 4. Output format
- By default, generates a single-line Lua wrapper after a header comment.
- `--compact` (or compiler API `Compact=true`) emits exactly one physical line, including a delimiter-safe comment header. This removes formatting only; it is not a compression algorithm.
- The generated runtime is intended for Lua 5.1-compatible environments. LuaJIT and Luau behavior must be tested for the target environment.

---

## 📊 Protection Profiles (Presets)

| Preset | Additional transforms before AzureVM | Decoy density | Friendly / Album Aliases |
| :--- | :--- | :---: | :--- |
| **`Clean`** / `Minify` | None (Minifier only) | — | `Lite` |
| **`Life`** / `Weak` | Constant Array (Threshold 1), Function Wrap | — | `Basic` |
| **`Standard`** / `Medium` | Encrypt Strings, Numbers to Expressions, Constant Array | — | `Balanced` |
| **`Solid`** / `Strong` | Double VM layer, String Encryption, Mutated Math | — | `Shield` |
| **`Luraph`** | Baseline AzureVM virtualization mode 14 | 1.0 | `Classic` |
| **`Luraph14`** | AST Pre-Mutation + VM mode 14 | 1.0 | `Stealth` |
| **`AzureGod`** | AST Pre-Mutation + Decoys 1.5x + VM mode 14 | 1.5 | 🎵 **`Khoidieu`** *(Chương 1 MONO)* |
| **`AzureGod15`** / `Luraph15` | AST Pre-Mutation + Decoys 1.5x + VM mode 15 | 1.5 | 🎵 **`Biendieu`** *(Chương 2 MONO)*, `Hardcore`, `Armor` |
| **`AzureGodUltra`** | Full Deep-CFF, Opaque Predicates, MBA 32-bit, Guards, SafeRetry | 1.5 | 🎵 **`Dudieu`** *(Chương 3 MONO)*, `Immortal`, `HardcoreUltra` |

The `14`/`15` suffix selects AzureVM's output-template mode, not a Luraph engine version. More transforms can increase output size and runtime cost; the table is not a security ranking.

---

## 🚀 Quick Start & CLI Usage

### Verified hardening

- Encoded payloads now carry a decoded-data checksum and fail before VM execution if modified. This detects simple corruption or edits; it is **not** a cryptographic signature and can be bypassed by an analyst who controls the output file.
- Default builds use OS randomness (`/dev/urandom` where available) instead of a seconds-resolution timestamp. `--seed` now controls the VM build as documented, so fixed-seed builds are reproducible. On platforms without `/dev/urandom`, the fallback is not cryptographically unpredictable.
- Run the focused checks with `lua5.1 tests/payload-integrity.lua && lua5.1 tests/seed-behavior.lua`.
- Run `lua5.1 tests/false-constants.lua` and `bash tests/verify-vm.sh Luraph` to verify VM output against Lua 5.1 behavior. The VM now preserves `false` and `nil` RK operands rather than losing them to the Lua `and/or` idiom.
- Each nested prototype now receives an independent instruction-field layout (three supported layouts), rather than sharing one layout across the whole output. Run `lua5.1 tests/per-prototype-layout.lua` for a ten-seed mixed-layout check. This raises static analysis effort but cannot prevent inspection of plaintext values during execution.
- Each instruction now selects one of those layouts using the preceding encoded word. Run `lua5.1 tests/chained-layout.lua` for an instruction-level decoding check across ten seeds. The VM and decoder still ship with the output, so this is not a guarantee against devirtualization.
- Chained layout decoding adds runtime work. In one local 10,000-iteration Lua 5.1 loop sample, median wall time rose from 0.1002 s to 0.1136 s (9 runs each). This is not a general performance benchmark; measure your own workload before deploying.
- The runtime releases the transient decoded payload buffer after materializing prototypes. This reduces retained plaintext copies; it does not make live VM state undumpable.
- New builds use 32-bit string lengths, rather than silently wrapping strings at 65,536 bytes. `lua5.1 tests/regression/string-constants.lua` checks binary strings, long strings, per-constant nonce diversity, ciphertext feedback, and fixed-seed reproducibility.
- Numeric packing uses Lua 5.1's [`math.frexp`](https://www.lua.org/manual/5.1/manual.html#pdf-math.frexp) instead of logarithmic exponent estimation. Serializer and AST regressions cover extreme doubles, signed zero, and precision-sensitive literals: `lua5.1 tests/regression/numeric-constants.lua` and `lua5.1 tests/regression/numeric-pipeline.lua`.
- Native-source preservation, limited preprocessing fallback, and binary-input rejection are checked with `lua5.1 tests/regression/source-preservation.lua`. Filename keywords no longer poison the runtime's decoding key; `lua5.1 tests/regression/runtime-filenames.lua` checks both templates and verifies an installed host debug hook remains active. Payload integrity checks are unchanged.

The string payload format is internal. Existing generated files keep their embedded decoder; newly generated files embed the updated decoder. Fixed seeds are reproducible within the same implementation, not a guarantee of byte-identical output across upgrades.

**Signed-zero compatibility:** AST output deliberately preserves the sign of a literal `-0`, including when transforms inject `+0` constants. This may differ from Lua 5.1's native constant-pooling quirks in programs mixing positive- and negative-zero literals. Check behavior on your target runtime if your code relies on this distinction.

These changes have **not** been benchmarked against Luraph and do not establish stronger protection than Luraph.

### Prerequisites
- **Lua 5.1** for compilation. The bytecode reader expects Lua 5.1 chunks; LuaJIT bytecode is not a supported compiler input.

### Tests and benchmarks
Run `bash scripts/check-lua51.sh` for the full quality gate: syntax checks, focused regressions, CLI validation, malformed-bytecode tests, and behavior comparisons across all six advertised presets. This Linux/Ubuntu runner requires Lua 5.1 and GNU `timeout`. To check one preset, run `bash scripts/check-lua51.sh Luraph`. Each semantic fixture has a 30-second timeout (`VM_TEST_TIMEOUT` overrides it).

`lua5.1 benchmark.lua 5` runs five measured samples per native Lua microbenchmark after a warm-up and prints median/min/max CPU time. `lua5.1 scripts/benchmark-vm.lua 5 > benchmark-vm.csv` compares native fixtures against the baseline AzureVM compiler using two fixed seeds, checks returned results on every run, and reports compile CPU time, output size, median execution CPU time, and slowdown. VM execution measurements include initialization/decoding on each invocation; they exclude Lua source parsing and do not measure the optional AST transforms. Benchmark ratios for very short native fixtures are sensitive to timer resolution. Benchmarks are informational: compare results on the same machine and Lua build; CI timings are not performance guarantees.

GitHub Actions runs syntax checks, regression tests, VM semantic comparisons, and the informational benchmark on pushes and pull requests. Pushing a stable version tag (for example `v2.0.0`) runs the release quality gate, verifies the CLI version matches the tag, and publishes the matching version's section from `CHANGELOG.md` as GitHub Release notes.

### CLI Syntax
```bash
lua azure_obf.lua <input.lua> [options]
```

### Options
```text
  -o, --out <file>       Output destination (default: <input>_protected.lua)
  --preset <name>        Select protection preset (default: Luraph)
                         Core choices: Luraph, Luraph14, Luraph15, AzureGod, AzureGod15, AzureGodUltra
                         MONO Album:   Khoidieu (Ch.1), Biendieu (Ch.2), Dudieu (Ch.3)
                         Diversified:  Clean, Life, Standard, Solid, Hardcore, Immortal
  --header <text>        Custom header comment in line 1
  --compact              Emit a single physical line, including header
  --retry-count <N>      Payload retries 0..100; also --retry-count=N (Ultra/Dudieu default: 3)
  --seed <number>        Integer 1..2147483647 for reproducible builds
  -v, --version          Display version information
  -h, --help             Display help menu
```

### Examples
```bash
# Basic daily protection (Life / Weak):
lua5.1 azure_obf.lua my_script.lua --preset Life --compact -o protected.lua

# MONO Album Chapter 1: Khoidieu (Khởi Điệu - AzureGod 1.5x decoys):
lua5.1 azure_obf.lua script.lua --preset Khoidieu --compact -o khoidieu.lua

# MONO Album Chapter 2: Biendieu (Biến Điệu - AzureGod15 Hardcore):
lua5.1 azure_obf.lua game.lua --preset Biendieu --compact -o biendieu.lua

# MONO Album Chapter 3: Dudieu (Đủ Điệu - AzureGodUltra Immortal):
# Full Deep-CFF + MBA 32-bit + Opaque Predicates + SafeRetryWrapper (3 retries):
lua5.1 azure_obf.lua game_logic.lua --preset Dudieu --compact --retry-count=3 -o dudieu.lua

# Custom branding header:
lua5.1 azure_obf.lua main.lua --preset Hardcore --header "Azure VM Security Engine" --compact -o main_obf.lua
```

---

## 📁 Repository Structure

```text
AzureVM/
├── azure_obf.lua           # Main CLI executable
├── README.md               # Documentation & guides
├── LICENSE                 # MIT License (with Prometheus attribution)
├── .gitignore              # Build and cache ignore patterns
├── examples/               # Sample testing scripts
│   └── demo.lua            # Feature verification test script
├── src/                    # Core source codebase
│   ├── presets.lua         # Protection preset definitions
│   ├── config.lua          # Runtime configuration
│   ├── logger.lua          # Formatted output logging
│   └── prometheus/
│       ├── azure_vm/       # Azure VM compiler, transpiler, and generator
│       │   ├── generator.lua   # Runtime builder & single-line code emitter
│       │   ├── encoder.lua     # Rolling cipher & polymorphic instruction packager
│       │   ├── reader.lua      # Bytecode parser
│       │   ├── transpiler.lua  # AST to VM IR transpiler
│       │   └── init.lua        # Module initializer
│       ├── steps/          # Transformation pipeline steps
│       │   ├── ControlFlowFlattening.lua  # CFF state machine transformer
│       │   ├── OpaquePredicates.lua       # Mathematical opaque predicate injector
│       │   ├── EncryptStrings.lua         # String encryption
│       │   ├── SplitStrings.lua           # String chunk splitting
│       │   ├── NumbersToExpressions.lua   # Numerical expression mutation
│       │   └── AzureVM.lua                # Main VM pipeline integration step
│       ├── compiler/       # AST Bytecode Compiler (Prometheus)
│       ├── parser.lua      # Parser & Tokenizer
│       ├── pipeline.lua    # Pipeline execution coordinator
│       └── unparser.lua    # AST Unparser
├── tests/                  # Integration test suite
├── scripts/                # Build and testing utilities
└── web/                    # Web-based obfuscation interface
```

---

## 🏷️ Tags & Keywords

`#lua` `#luau` `#roblox` `#obfuscator` `#lua-obfuscator` `#roblox-script` `#lua-vm` `#virtual-machine` `#bytecode-compiler` `#roblox-executor` `#anti-tamper` `#control-flow-flattening` `#obfuscation` `#lua51` `#prometheus` `#security`

---

## 📜 License & Roadmap

Distributed under the **MIT License**.

- **Prometheus Lua Obfuscator:** Copyright (c) [levno-710](https://github.com/prometheus-lua) (MIT License).
- **Azure VM Additions & Engine:** Copyright (c) 2026 **Azure**.

> Development status and release cadence should be verified from the repository history.

## Current hardening update: use and limits

```sh
lua5.1 azure_obf.lua input.lua --preset AzureGodUltra --compact --seed 12345 -o protected.lua
bash scripts/check-lua51.sh  # tests also require Python 3 and GNU timeout
lua5.1 scripts/benchmark-vm.lua 3
```

This update adds mapped register storage, on-demand string decoding, and a true single-line CLI/API output option. Existing opcode randomization, chained instruction encoding, payload checksum validation, and eligible-block CFF/opaque predicates remain in place. An integrity checksum detects accidental corruption; it is not authentication against an analyst who can modify the decoder and checksum together.

`AzureGodUltra` now also enables deep-CFF, bounded MBA constant hiding, initialization capability/library-identity checks, and at most two initialization retries. Recovery selects xpcall, pcall, or a non-yielding coroutine fallback according to availability. Integrity failures are terminal. User code starts **after initialization recovery** ends. Ultra additionally enables the separate `SafeRetryWrapper` described below, which deliberately replays whole payloads after uncaught errors.

These are not universal anti-dump/anti-hook/anti-environment-spy traps. Library identity changes during initialization and broken primitive canaries fail closed; preinstalled behaviorally equivalent hooks and environment loggers are not reliably detectable. Required functions are locally captured, transient buffers are cleared, and the encoded user payload is interpreted without requiring native dump/load/debug APIs. Live VM state and initial global lookups remain visible to a controlling host. Host debug hooks remain untouched.

Compiler API options are `RuntimeChecks=true` and `InitializationRetries=0..2`; both default off/zero outside Ultra. The fallback is initialization-only, not a transaction/recovery system for user programs. `--compact` removes formatting; it does not compress or encrypt by itself.

Run `python3 scripts/check-runtime-matrix.py` to compare compact Ultra output against the Lua 5.1 baseline on installed Lua 5.1, LuaJIT, and Luau CLI executables. Missing runtimes are reported as skipped; executable hashes identify the tested binaries. This is not certification of Roblox executors, complete Luau source-dialect support, all input programs, or Luraph superiority. See [the hardening contract](docs/ultra-hardening.md).

## SafeRetryWrapper: stateless payload replay

`SafeRetryWrapper` is an optional pipeline step **after AzureVM**, enabled by default in `AzureGodUltra` with `RetryCount=3`. Its name refers to bounded attempts and fresh VM state, **not side-effect safety**.

```sh
lua5.1 azure_obf.lua input.lua --preset AzureGodUltra --compact --retry-count=3 -o protected.lua
lua5.1 azure_obf.lua input.lua --preset AzureGodUltra --compact --retry-count=0 -o no_payload_retry.lua
```

Both `--retry-count=N` and `--retry-count N` are accepted. The integer range is 0..100. **N means additional retries**: 3 permits at most 4 total attempts. Zero removes the wrapper entirely. A positive CLI override adds the step to other AzureVM presets; non-VM presets cannot enable it.

Each failed attempt unwinds its protected call and runs the entire emitted decoder/VM factory again. Registers, VM stack, instruction tables (including root tailcall cleanup), prototype state, and upvalues are recreated. Original argument values are passed again; mutable argument objects are not cloned. Nil/false/multiple results are preserved on success, and the final error object is rethrown unchanged. xpcall is preferred, with pcall as the availability fallback.

**External effects are deliberately retained and may repeat:** globals, writes, requests, counters, host mutations, and escaped closures are not rolled back. An escaped closure remains attached to its original attempt. The wrapper does not infer that a script is stateless.

Every uncaught factory/dispatcher error is eligible for replay, including integrity rejection. Checks still reject corrupt payloads on every attempt; retries do not repair or bypass them. InitializationRetries applies independently inside each payload attempt. Native crashes, process termination, infinite loops, and non-catchable resource failures are not handled.

Lua 5.1 protected calls introduce a yield boundary: a top-level payload yield through pcall/xpcall is not supported and may become a retried error. Disable whole-payload retry with `--retry-count=0` for scripts requiring that behavior. Ordinary coroutines entirely inside the payload remain covered by the semantic test suite.

For custom pipeline configurations, append `{Name="SafeRetryWrapper", Settings={RetryCount=3}}` immediately after the AzureVM step. The direct compiler API still emits an unwrapped VM unless this pipeline step is used.
