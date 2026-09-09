# Azure VM (AzureObf)

<div align="center">

```text
       ___                             ____  __      ____  
      /   | ____  __  __________      / __ \/ /_    / __/  
     / /| |/_  / / / / / ___/ _ \    / / / / __ \  / /_    
    / ___ | / /_/ /_/ / /  /  __/   / /_/ / /_/ / / __/    
   /_/  |_|/___/\__,_/_/   \___/    \____/_.___(_)_/       
```

### High-Performance Lua & Luau Polymorphic Virtual Machine Obfuscator
*Custom Virtual ISA • State-Chained Feedback Cipher • Control Flow Flattening • Zero-Freeze Executor Runtime*

[![GitHub Stars](https://img.shields.io/github/stars/LionHub-Pino/AzureVM?style=flat-square&color=yellow)](https://github.com/LionHub-Pino/AzureVM/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/LionHub-Pino/AzureVM?style=flat-square&color=blue)](https://github.com/LionHub-Pino/AzureVM/network/members)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=flat-square)](LICENSE)
[![Lua 5.1](https://img.shields.io/badge/Lua-5.1-blue.svg?style=flat-square)](https://www.lua.org/)
[![Luau](https://img.shields.io/badge/Luau-Compatible-brightgreen.svg?style=flat-square)](https://luau-lang.org/)
[![Roblox](https://img.shields.io/badge/Roblox-Mobile%20%26%20PC-red.svg?style=flat-square)](https://www.roblox.com/)
[![Base Library: Prometheus](https://img.shields.io/badge/Base%20Library-Prometheus-blueviolet.svg?style=flat-square)](https://github.com/prometheus-lua/Prometheus)

</div>

---

## 📌 Attribution & Credits

> [!IMPORTANT]
> **Base Library Notice:**  
> **Azure VM** is built on top of the open-source pipeline of **[Prometheus Lua Obfuscator](https://github.com/prometheus-lua/Prometheus)** created by **levno-710**.
>
> - **Prometheus Core:** Powers our foundational parsing, lexing, Abstract Syntax Tree (AST) manipulation, scope resolution, and AST unparsing infrastructure.
> - **Azure VM Additions:** Developed by **Azure**, adding our proprietary polymorphic bytecode compiler, dynamic per-function instruction generation, rolling state-chained feedback cipher, Control Flow Flattening (CFF), opaque mathematical predicates, memory auto-purging, and a high-speed zero-freeze dispatch runtime tuned specifically for Roblox execution engines.

---

## ✨ Overview

**Azure VM** is a next-generation virtualization and code protection system engineered specifically for Lua 5.1 and Luau environments (including Roblox Mobile and PC executors). 

Traditional obfuscators rely merely on string encryption, variable renaming, or easily-patterned macro substitution. Azure VM converts your source code into a custom, non-standard virtual bytecode stream executed inside a lightweight, sandboxed virtual interpreter. Every function receives randomized opcodes, dynamically mutated instruction formats, and rolling feedback encryption keys, rendering automated deobfuscators, AST pattern matchers, and static decompilers ineffective.

---

## 🌟 Key Architecture & Features

### 1. ⚡ Zero-Freeze Roblox Executor Optimization
- **Precomputed Lookup Table (`v[c]`):** Bytecode unpacker utilizes high-speed static lookup tables, reducing decryption time to under **2–5 milliseconds**.
- **No Watchdog Timeouts:** Designed from the ground up to never stall the Roblox main thread or trigger script timeout warnings on mobile executors (Delta, Fluxus, Codex, Arceus X) and PC executors (Wave, Solara, Synapse Z).
- **RAM Auto-Purge:** Interpreter automatically clears bytecode chunks, decompression buffers, and initialization tables immediately after mounting to maintain a near-zero memory footprint.

### 2. 🔀 Polymorphic Virtual ISA & Dynamic Encryption
- **Unique Per-Build Opcode Mapping:** Every build generates a distinct set of mathematical relationships and opcode dispatch tables.
- **State-Chained Feedback Cipher:** Instructions are encoded through a rolling keystream cipher where each encrypted instruction influences the key of the next, preventing partial-block substitution attacks.
- **Instruction Field Shuffling:** Bitwise slot layouts for registers, operands, and constant pool indices mutate dynamically across compilation passes.

### 3. 🛡️ Advanced AST Mutation Pipeline
- **Control Flow Flattening (CFF):** Restructures linear statement blocks into state-driven dispatch loops with randomized transition graphs.
- **Opaque Predicates:** Injects mathematically invariant condition blocks (e.g., constant algebraic identities) that confuse static analysis tools and data-flow analyzers.
- **String Encryption & Splitting:** Splits sensitive strings across non-contiguous arrays and resolves them with dynamic seed keys at runtime.
- **Numbers to Expressions:** Transforms integers and floats into nested mathematical expressions.

### 4. 📦 Compact Single-Line Delivery
- Generates clean, ready-to-deploy single-line outputs: `return(function(...) ... end)(...);`.
- Zero external runtime dependencies — executes directly in standard vanilla Lua 5.1, LuaJIT, and Luau.

---

## 📊 Protection Profiles (Presets)

| Preset | Virtual Machine | AST Transformations | Protection Level | Recommended Use Case |
| :--- | :--- | :--- | :---: | :--- |
| **`Luraph`** | Azure VM Standard | Clean VM Packaging | ⭐⭐⭐⭐ | Fast deployment, minimal file size |
| **`Luraph14`** | Azure VM Enhanced | String Encryption + Splitting | ⭐⭐⭐⭐⭐ | General Roblox scripts & utilities |
| **`Luraph15`** | Azure VM Ultra | Strings + Number Expressions + Decoy Traps | ⭐⭐⭐⭐⭐+ | Commercial & private gaming hubs |
| **`AzureGod`** | Azure VM Enhanced | Deep AST Pre-Mutation + VM | ⭐⭐⭐⭐⭐⭐ | High-value game logic & anti-cheat |
| **`AzureGod15`** | Azure VM Ultra | Full Pipeline + Decoy Opcodes (1.5x) | 👑 **Elite** | Maximum deobfuscation resistance |
| **`AzureGodUltra`** | Azure VM Ultra | **CFF + Opaque Predicates + Full Pipeline** | 🔱 **Supreme** | The ultimate defense against decompilers |

---

## 🚀 Quick Start & CLI Usage

### Prerequisites
- **Lua 5.1** or **LuaJIT** installed on Linux, Termux (Android), macOS, or Windows.

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

> *Active development in progress. Regular updates, bug fixes, and security enhancements are deployed weekly.*
