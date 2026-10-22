#!/usr/bin/env bash
set -uo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
preset="${1:-Luraph}"
timeout="${VM_TEST_TIMEOUT:-30s}"
extra_args=()
compact=0
if [ "${2:-}" = "--compact" ] && [ "$#" -le 2 ]; then
    extra_args=(--compact)
    compact=1
elif [ "$#" -gt 1 ]; then
    echo 'Usage: verify-vm.sh [preset] [--compact]' >&2
    exit 1
fi
command -v timeout >/dev/null || { echo 'GNU timeout is required' >&2; exit 1; }
passed=0
failed=0

for source in "$repo"/tests/*.lua; do
    name="$(basename "$source")"
    case "$name" in
        false-constants.lua|payload-integrity.lua|seed-behavior.lua|per-prototype-layout.lua|chained-layout.lua) continue ;;
    esac

    rm -f "$tmp/actual" "$tmp/actual.err"

    timeout "$timeout" lua5.1 "$source" >"$tmp/expected" 2>"$tmp/expected.err"
    expected_status=$?
    timeout "$timeout" lua5.1 "$repo/azure_obf.lua" "$source" --preset "$preset" --seed 12345 \
        "${extra_args[@]}" -o "$tmp/output.lua" >"$tmp/build.log" 2>&1
    build_status=$?
    if [ "$build_status" -eq 0 ] && [ "$compact" -eq 1 ]; then
        if [ ! -s "$tmp/output.lua" ] || [ "$(wc -l < "$tmp/output.lua")" -ne 0 ] || LC_ALL=C grep -q $'\r' "$tmp/output.lua"; then
            echo 'Compact output is empty or contains CR/LF' >>"$tmp/build.log"
            build_status=98
        fi
    fi
    if [ "$build_status" -eq 0 ]; then
        timeout "$timeout" lua5.1 "$tmp/output.lua" >"$tmp/actual" 2>"$tmp/actual.err"
        actual_status=$?
    else
        actual_status=99
    fi

    if [ "$expected_status" -eq 0 ] && [ "$build_status" -eq 0 ] && \
        [ "$actual_status" -eq 0 ] && cmp -s "$tmp/expected" "$tmp/actual"; then
        printf 'PASS %s\n' "$name"
        passed=$((passed + 1))
    else
        printf 'FAIL %s (source=%s, build=%s, VM=%s)\n' \
            "$name" "$expected_status" "$build_status" "$actual_status"
        failed=$((failed + 1))
        tail -n 8 "$tmp/build.log" >&2
        cat "$tmp/expected.err" >&2
        if [ -f "$tmp/actual.err" ]; then cat "$tmp/actual.err" >&2; fi
        if [ -f "$tmp/actual" ]; then diff -u "$tmp/expected" "$tmp/actual" >&2 || true; fi
    fi
done

printf '%s: %s passed, %s failed\n' "$preset" "$passed" "$failed"
[ "$failed" -eq 0 ]
