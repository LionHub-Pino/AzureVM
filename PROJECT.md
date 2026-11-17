# Project: AzureVM (v3.0.0 Pure VM)

## Core Mission
AzureVM is an ultra-hardened, production-grade Lua 5.1/Luau bytecode virtualizer and code protection engine. It transforms Lua scripts into custom-encoded virtual machine bytecode executed by a polymorphic, anti-tamper virtual machine runtime with Luraph v15.2 parity.

## Core Architectural Stack
- **AST & Lexical Pipeline Foundation**: Prometheus (by levno-710)
- **Virtual Machine Engine**: AzureVM Pure Polymorphic Virtual Machine Architecture
  - Multi-Handler Opcode Splitting: 76 distinct polymorphic handlers (2 variants per Lua 5.1 opcode).
  - Dynamic Register Key Rolling & Frame Salting (`CALL_CNT * 79`).
  - Sealed Metatable Proxy for dispatch tables and virtual registers (`__metatable = false`).
  - Native 128-bit 2-pass Bidirectional S-Box ARX Cipher (`mksbox`).
  - Anti-Hook & Anti-Tamper Armor for Roblox Executors (C-closure verification, hook scanners, traceback monitors).
- **Target Runtimes**: Lua 5.1, LuaJIT, Luau (Roblox Executors: Synapse, Wave, Solara, Delta, Hydrogen, Codex).
- **Repository**: `https://github.com/LionHub-Pino/AzureVM`
