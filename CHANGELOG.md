# Changelog

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
