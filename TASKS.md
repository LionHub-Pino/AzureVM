# Tasks: AzureVM Roadmap

## Completed (v3.0.0 Release)
- [x] Multi-Handler Opcode Splitting: 76 polymorphic handlers across 38 opcodes with alternating ciphertext selection.
- [x] Dynamic Register Permutation & Frame Salting (`CALL_CNT * 79`) with sealed `REG` (`__metatable = false`).
- [x] Roblox Executor Anti-Hook & Anti-Tamper Armor (C-closure verification, hook scanners, traceback monitors).
- [x] Pure VM presets (`Luraph15_Ultra`, `PureVM`, `pure`) with zero AST pre-transform passes.
- [x] 100% test pass across all regression, CLI, harness, Luau, and E2E suites.
- [x] Git release tagged `v3.0.0`, pushed to remote, and published to GitHub Releases.
- [x] 1-Click Roblox Executor payload uploaded to Pastefy (`https://pastefy.app/eX1wTF1Y/raw`).

## Backlog
- [ ] JIT trace-abort suppression for low-end Android Roblox executors.
- [ ] Optional multi-pass variable name permutation dictionary expansions.
