# Memory: AzureVM Architecture & Decisions

## Key Architectural Decisions (ADR)
1. **Multi-Handler Opcode Splitting (v3.0.0)**:
   - Problem: Standard VMs provide a 1-to-1 mapping between Lua opcodes and handlers, making static opcode reconstruction trivial for deobfuscators.
   - Solution: Every opcode $0 \dots 37$ is assigned two distinct global opcodes in range $1 \dots 250$ (`opcode_map` and `opcode_map2`), generating 76 polymorphic handlers. Instructions alternate between variants using dynamic running ciphertext feedback: `variant = ((i + prev_enc) % 2 == 0) and 1 or 2`.
   - Handler 36 (`OP_CLOSURE`) recognizes both variant 1 (`O[0]`) and variant 2 (`O2[0]`) for child prototype upvalue pseudo-instructions.

2. **Per-Activation Frame Salting & Sealed Register Bank (v3.0.0)**:
   - Problem: Cross-frame register dumps or metatable inspection of `REG` could leak internal state.
   - Solution: Virtual register bank `REG` is protected with `__metatable = false`. Virtual storage offsets are dynamically salted with `SHIFT = (SHIFT_SALT + PR[P_OA] * SHIFT_MUL + CALL_CNT * 79) % 4294967296`, isolating activation frames.

3. **Elimination of Prometheus AST Transformations in Core Presets**:
   - Problem: AST transformations like `EncryptStrings` create signature functions (e.g. `main_1`) and predictable AST patterns easily intercepted by AST pattern deobfuscators.
   - Solution: Core profiles (`Luraph`, `PureVM`, `Luraph15_Ultra`) rely exclusively on pure VM virtualization and native S-box ARX decryption.

4. **Attribution Invariant**:
   - All documentation and commits must credit **Prometheus** (by levno-710) as the AST pipeline foundation.
