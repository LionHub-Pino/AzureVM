# AzureVM Software Protection Threat Model & Evaluation

## 1. Executive Summary & Philosophy

AzureVM is an open-source, Lua 5.1 bytecode-virtualizing obfuscator built on top of the Prometheus pipeline.

> [!IMPORTANT]
> **No Secret Keys in Output:**  
> In any purely software-based interpreter distribution running on untrusted hardware, the runtime interpreter, decoder, opcode dispatch table, and key materials **must reside inside the output file**. Therefore, AzureVM does not claim absolute protection against extraction or devirtualization. Claims of "100% unbreakable" or "anti-dump absolute" are technically inaccurate and rejected by this engineering specification.

Instead, AzureVM aims to maximize the **reverse engineering work factor per unit of runtime cost**, forcing an analyst to undertake labor-intensive static and dynamic devirtualization while preserving deterministic Lua 5.1/Luau execution semantics.

---

## 2. Threat Model & Adversary Capabilities

We define the adversary as an analyst or automated tool running in an environment fully controlled by the adversary:

| Threat / Attack Vector | Adversary Capability | AzureVM Countermeasure & Architecture | Realistic Security Boundary & Limitations |
| :--- | :--- | :--- | :--- |
| **Static Bytecode Extraction** | Parsing dumped files, looking for standard Lua chunks (`\27Lua`). | AzureVM compiles to an internal custom binary structure, scrambled opcodes, and packing. | Custom decoder is embedded; an analyst can inspect `Generator` logic to write an unpacker. |
| **String Extraction / Memory Inspection** | `strings` utility, memory dumping process space. | On-demand string decoding with unique per-string nonce and ciphertext feedback. Plaintext cache avoided. | Live strings decrypted during execution become resident in memory and remain observable. |
| **Opcode Frequency Analysis** | Statistical analysis of opcode occurrences to map handlers. | Opcode remapping (`(op * mul + add) % 256`), dynamic decoy handlers, state-chained instruction encoding. | Dynamic execution traces can isolate executed handlers from unexecuted decoys. |
| **Control Flow Graph (CFG) Recovery** | Graph analysis decompilers (e.g. IDA, Ghidra, Lua deobfuscators). | Bottom-up Deep Control Flow Flattening (Deep-CFF) with opaque state predicates. | Complex symbolic execution engines can solve opaque polynomial predicates $s(s+1) \equiv 0 \pmod 2$. |
| **Arithmetic / Constant Recovery** | Constant folding, AST simplification. | Mixed Boolean-Arithmetic (MBA) 32-bit integer identities without bit library dependency. | SMT solvers (Z3) can normalize MBA identities into canonical expressions. |
| **Runtime Tampering & Hooks** | Replacing host primitives (`pcall`, `string.byte`, `setmetatable`). | Canaries and capability verification with fail-closed errors. | Host hooks with identical semantics (e.g., standard profilers) are intentionally permitted. |
| **Uncaught Error Loops & Side Effects** | Scripts failing during execution or retrying in loops. | Retry Engine v3: Bounded initialization recovery vs optional idempotent payload retry. | Payload replay deliberately re-executes external host writes; not suitable for non-idempotent scripts without consent. |

---

## 3. Reverse Engineering Complexity Evaluation

We benchmarked the reverse engineering cost across protection presets:

| Metric / Protection Level | `Fast` | `Balanced` | `Khoidieu` (Ch. 1) | `Biendieu` (Ch. 2) | `Dudieu` (Ch. 3 / Hardened) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Code Size Expansion** | ~50x | ~45x (minified) | ~75x - 85x | ~80x - 90x | ~100x - 110x |
| **Decoy Handler Count** | ~5 - 9 | ~25 - 45 | ~37 - 67 | ~37 - 67 | ~37 - 67 |
| **Template Mode** | 14 | 14 | 14 | 15 (integrity) | 15 (deep integrity) |
| **CFG Complexity (Cyclomatic)** | 1 (dispatcher) | Low AST mutation | Medium AST | High AST mutation | High Dispatcher + Flattened Blocks |
| **Static Analysis Time (Human)** | ~15 - 30 mins | ~1 - 2 hours | ~2 - 4 hours | ~4 - 6 hours | Several days / Requires custom AST desanitizer |

---

## 4. Operational Best Practices

1. **Deterministic Builds:** Always supply `--seed <number>` in CI/CD pipelines to ensure reproducible builds.
2. **Idempotence Verification:** Only enable `--retry-count` on stateless, idempotent scripts (e.g., pure computation, read-only routines).
3. **Execution Profiling:** Use `--preset Fast` for high-frequency game render loops (60-120 FPS), and `--preset Dudieu` or `--preset Hardened` for sensitive authentication and license validation routines.
