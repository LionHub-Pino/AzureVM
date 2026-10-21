#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for script in benchmark.lua scripts/benchmark-vm.lua; do
    for value in nope 0 -1 1.5 101 nan; do
        if lua5.1 "$repo/$script" "$value" >"$tmp/log" 2>&1; then
            printf 'FAIL: %s accepted %s\n' "$script" "$value" >&2
            exit 1
        fi
        grep -q 'usage:' "$tmp/log"
    done
done
printf 'benchmark validation: ok\n'
