#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf 'print("cli fixture")\n' > "$tmp/input.lua"
reject() {
    if lua5.1 "$repo/azure_obf.lua" "$tmp/input.lua" -o "$tmp/output.lua" "$@" >"$tmp/log" 2>&1; then
        printf 'FAIL: CLI accepted invalid arguments: %s\n' "$*" >&2
        exit 1
    fi
    grep -q 'Error:' "$tmp/log"
    test ! -e "$tmp/output.lua"
}
reject --preset typo
reject --preset
reject --seed nope
reject --seed 1.5
reject --seed 0
reject --seed -1
reject --seed 2147483648
reject --seed
reject --unknown
reject --out
reject --header
reject "$tmp/extra.lua"
lua5.1 "$repo/azure_obf.lua" "$tmp/input.lua" --seed 12345 -o "$tmp/a.lua" >"$tmp/log" 2>&1
lua5.1 "$repo/azure_obf.lua" "$tmp/input.lua" --seed 12345 -o "$tmp/b.lua" >>"$tmp/log" 2>&1
cmp "$tmp/a.lua" "$tmp/b.lua"
test "$(lua5.1 "$tmp/a.lua")" = 'cli fixture'
lua5.1 "$repo/azure_obf.lua" "$tmp/input.lua" --preset Luraph14 --seed 12345 -o "$tmp/c.lua" >>"$tmp/log" 2>&1
lua5.1 "$repo/azure_obf.lua" "$tmp/input.lua" --preset Luraph14 --seed 12345 -o "$tmp/d.lua" >>"$tmp/log" 2>&1
cmp "$tmp/c.lua" "$tmp/d.lua"
test "$(lua5.1 "$tmp/c.lua")" = 'cli fixture'
printf 'CLI validation: ok\n'
