#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf "=== AzureVM Luau v15.2 Transpiler & VM Validation ===\n"

# 1. Compile luau-v15.luau using Luraph15_2 preset
lua5.1 "$repo/azure_obf.lua" "$repo/tests/luau-v15.luau" --preset Luraph15_2 --seed 12345 -o "$tmp/out_15_2.lua" >"$tmp/build.log" 2>&1

# 2. Execute compiled VM output with lua5.1
output="$(lua5.1 "$tmp/out_15_2.lua")"

# 3. Assert expected outputs
assert_contains() {
    local needle="$1"
    if ! echo "$output" | grep -Fq "$needle"; then
        printf "FAIL: Expected output to contain '%s'\nGot:\n%s\n" "$needle" "$output" >&2
        exit 1
    fi
}

assert_contains "Welcome back, AzureWarrior! Base score: 42"
assert_contains "Status:	ELITE"
assert_contains "Calculated total:	0"
assert_contains "Joined text:	AzureVM_v1.5.2"
assert_contains "Compute output:	120"

printf "Luau transpiler and VM execution: OK (Luraph15_2)\n"

# 4. Also test with default preset Luraph
lua5.1 "$repo/azure_obf.lua" "$repo/tests/luau-v15.luau" --preset Luraph --seed 54321 -o "$tmp/out_luraph.lua" >>"$tmp/build.log" 2>&1
output_luraph="$(lua5.1 "$tmp/out_luraph.lua")"

if ! echo "$output_luraph" | grep -Fq "Compute output:	120"; then
    printf "FAIL: Luraph default preset failed on luau-v15.lua\n" >&2
    exit 1
fi

printf "Luau transpiler and VM execution: OK (Luraph)\n"
printf "ALL LUAU VALIDATION TESTS PASSED!\n"
