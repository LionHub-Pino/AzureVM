#!/usr/bin/env bash
# Non-Docker quality gate; Ubuntu/Linux with Lua 5.1 and GNU timeout.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
luac5.1 -p azure_obf.lua cli.lua benchmark.lua
find src tests scripts examples -type f -name '*.lua' -print0 | xargs -0 -n1 luac5.1 -p
for test in payload-integrity seed-behavior false-constants per-prototype-layout chained-layout; do
    lua5.1 "tests/$test.lua"
done
lua5.1 tests/regression/reader-validation.lua
lua5.1 tests/regression/numeric-constants.lua
lua5.1 tests/regression/numeric-hex-range.lua
lua5.1 tests/regression/numeric-pipeline.lua
lua5.1 tests/regression/string-constants.lua
lua5.1 tests/regression/lazy-strings.lua
lua5.1 tests/regression/register-mapping.lua
lua5.1 tests/regression/compact-output.lua
lua5.1 tests/regression/source-preservation.lua
lua5.1 tests/regression/runtime-filenames.lua
lua5.1 tests/regression/benchmark-statistics.lua
bash tests/cli-validation.sh
bash tests/compact-cli.sh
bash tests/benchmark-validation.sh
bash tests/harness-validation.sh
if [ "$#" -eq 0 ]; then
    set -- Luraph Luraph14 Luraph15 AzureGod AzureGod15 AzureGodUltra
fi
for preset in "$@"; do bash tests/verify-vm.sh "$preset"; done
