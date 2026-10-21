# Changelog

## Unreleased

### Fixed
- CLI rejects missing option values, unknown options/presets, extra inputs, and invalid seeds instead of silently falling back to different settings.
- Fixed-seed CLI builds now seed both the AST transforms and VM encoder for reproducible advanced-preset output.
- Bytecode reader bounds-checks integers, doubles, strings, counts, and debug data; rejects truncated chunks, unsupported large string lengths, missing string terminators, excessive prototype nesting, and trailing data.
- Benchmark sample validation rejects nonnumeric input, and even-sized samples use the average of the two middle values.

### Added
- A shared Lua 5.1 quality gate covering all six advertised AzureVM presets, CLI behavior, and malformed-bytecode regression tests.
- Per-fixture timeouts and stricter success requirements in the VM comparison harness.
- Native-versus-VM benchmark CSV reports with correctness checks, two fixed seeds, compile cost, output size, and median execution time including VM startup/decoding.

## [1.0.0] - 2026-10-21

First versioned AzureVM release.

### Added
- CI for Lua 5.1 syntax checks, regression tests, and VM behavior comparisons.
- Repeatable, warm-up-adjusted Lua 5.1 microbenchmarks that report median/min/max CPU time. Results are informational and environment-dependent.
- Independent per-prototype and chained per-instruction VM field layouts.
- Payload corruption checks, deterministic seeded builds, OS-randomized default build seeds, and transient decoded-payload cleanup.

### Changed
- CLI version now reports `AzureVM v1.0.0`.

### Security and compatibility notes
- The payload checksum is an integrity check, not a cryptographic signature or anti-tamper guarantee.
- Obfuscation does not keep runtime code or values secret from an analyst controlling the execution environment.
- Lua 5.1 is the supported bytecode compiler/runtime baseline. Luau and executor compatibility are not established by this release's test suite.
