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

Obfuscation can increase reverse-engineering effort, but it does not make code secret once it runs on a machine controlled by an analyst. The output contains the VM and its decoder; live values can be inspected or dumped. No claim of resistance to a particular deobfuscator is made without a reproducible test.

Preset names containing **`Luraph`** are historical compatibility names for AzureVM configurations. This project is not Luraph, is not affiliated with Luraph, and has not been shown to match or exceed Luraph v15.

---

## 🌟 Key Architecture & Features

### 1. Runtime and memory
- Uses a byte lookup table during payload decoding.
- Clears the transient decoded payload buffer after materializing prototypes. Live VM state remains in memory while needed.
- Load time, runtime overhead, memory use, and executor timeout behavior depend on the script and environment; no universal bounds are claimed.

### 2. 🔀 Polymorphic Virtual ISA & Dynamic Encryption
- **Seeded opcode mapping:** The build seed controls a shuffled opcode map. Fixed seeds produce reproducible output.
- **Rolling instruction encoding:** Each encoded instruction contributes to the key used for the next instruction. The decoder and key material are included in the generated file.
- **Per-prototype field layouts:** Nested functions can use different arrangements of instruction fields.

### 3. 🛡️ Advanced AST Mutation Pipeline
- **Control Flow Flattening (CFF):** Available in the `AzureGodUltra` preset for eligible statement blocks.
- **Opaque Predicates:** Available in the `AzureGodUltra` preset.
- **String transforms:** `SplitStrings` and `EncryptStrings` are enabled in the non-default advanced presets.
- **Numbers to Expressions:** Enabled in the non-default advanced presets.

### 4. Output format
- Generates a single-line Lua wrapper after a header comment.
- The generated runtime is intended for Lua 5.1-compatible environments. LuaJIT and Luau behavior must be tested for the target environment.

---

## 📊 Protection Profiles (Presets)

| Preset | Additional transforms before AzureVM | Decoy density |
| :--- | :--- | :---: |
| **`Luraph`** | None | 1.0 |
| **`Luraph14`**, **`Luraph15`** | Split strings, encrypt strings, numbers to expressions | 1.0 / 1.2 |
| **`AzureGod`**, **`AzureGod15`** | Split strings, encrypt strings, numbers to expressions | 1.5 |
| **`AzureGodUltra`** | Above, plus eligible-block CFF and opaque predicates | 1.5 |

The `14`/`15` suffix selects AzureVM's output-template mode, not a Luraph engine version. More transforms can increase output size and runtime cost; the table is not a security ranking.

---

## 🚀 Quick Start & CLI Usage

### Verified hardening

- Encoded payloads now carry a decoded-data checksum and fail before VM execution if modified. This detects simple corruption or edits; it is **not** a cryptographic signature and can be bypassed by an analyst who controls the output file.
- Default builds use OS randomness (`/dev/urandom` where available) instead of a seconds-resolution timestamp. `--seed` now controls the VM build as documented, so fixed-seed builds are reproducible. On platforms without `/dev/urandom`, the fallback is not cryptographically unpredictable.
- Run the focused checks with `lua5.1 tests/payload-integrity.lua && lua5.1 tests/seed-behavior.lua`.
- Run `lua5.1 tests/false-constants.lua` and `bash tests/verify-vm.sh Luraph` to verify VM output against Lua 5.1 behavior. The VM now preserves `false` and `nil` RK operands rather than losing them to the Lua `and/or` idiom.
- Each nested prototype now receives an independent instruction-field layout (three supported layouts), rather than sharing one layout across the whole output. Run `lua5.1 tests/per-prototype-layout.lua` for a ten-seed mixed-layout check. This raises static analysis effort but cannot prevent inspection of plaintext values during execution.
- The runtime releases the transient decoded payload buffer after materializing prototypes. This reduces retained plaintext copies; it does not make live VM state undumpable.

These changes have **not** been benchmarked against Luraph and do not establish stronger protection than Luraph.

### Prerequisites
- **Lua 5.1** for compilation. The bytecode reader expects Lua 5.1 chunks; LuaJIT bytecode is not a supported compiler input.

### CLI Syntax
```bash
lua azure_obf.lua <input.lua> [options]
```

### Options
```text
  -o, --out <file>       Output destination (default: <input>_protected.lua)
  --preset <name>        Select protection preset (default: Luraph)
                         Choices: Luraph, Luraph14, Luraph15, AzureGod, AzureGod15, AzureGodUltra
  --header <text>        Custom header comment in line 1
  --seed <number>        Deterministic PRNG seed for reproducible builds
  -v, --version          Display version information
  -h, --help             Display help menu
```

### Examples
```bash
# Basic protection
lua azure_obf.lua my_script.lua -o protected.lua

# Maximum protection with Control Flow Flattening & Opaque Predicates:
lua azure_obf.lua game_logic.lua --preset AzureGodUltra -o game_protected.lua

# Custom branding header:
lua azure_obf.lua main.lua --preset AzureGod15 --header "Azure VM Security Engine" -o main_obf.lua
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
