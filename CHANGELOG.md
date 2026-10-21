# Changelog

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
