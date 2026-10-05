#!/usr/bin/env bash
set -u

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
preset="${1:-Luraph}"
passed=0
failed=0

for source in "$repo"/tests/*.lua; do
    name="$(basename "$source")"
    case "$name" in
        false-constants.lua|payload-integrity.lua|seed-behavior.lua) continue ;;
    esac

    lua5.1 "$source" >"$tmp/expected" 2>"$tmp/expected.err"
    expected_status=$?
    lua5.1 "$repo/azure_obf.lua" "$source" --preset "$preset" --seed 12345 \
        -o "$tmp/output.lua" >"$tmp/build.log" 2>&1
    build_status=$?
    if [ "$build_status" -eq 0 ]; then
        lua5.1 "$tmp/output.lua" >"$tmp/actual" 2>"$tmp/actual.err"
        actual_status=$?
    else
        actual_status=99
    fi

    if [ "$expected_status" -eq "$actual_status" ] && cmp -s "$tmp/expected" "$tmp/actual"; then
        printf 'PASS %s\n' "$name"
        passed=$((passed + 1))
    else
        printf 'FAIL %s (source=%s, build=%s, VM=%s)\n' \
            "$name" "$expected_status" "$build_status" "$actual_status"
        failed=$((failed + 1))
    fi
done

printf '%s: %s passed, %s failed\n' "$preset" "$passed" "$failed"
[ "$failed" -eq 0 ]
