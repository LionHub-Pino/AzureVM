# Changelog

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
