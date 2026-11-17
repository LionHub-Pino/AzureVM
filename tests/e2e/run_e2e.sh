#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

MODE="all"
case "${1:-}" in
    ""|--all) MODE="all" ;;
    --tiers-only) MODE="tiers" ;;
    --r1) MODE="r1" ;;
    --r2) MODE="r2" ;;
    -h|--help)
        echo "Usage: $0 [--tiers-only | --r1 | --r2 | --all]"
        exit 0
        ;;
    *)
        echo "Unknown option: $1" >&2
        echo "Usage: $0 [--tiers-only | --r1 | --r2 | --all]" >&2
        exit 1
        ;;
esac

if [ "$#" -gt 1 ]; then
    echo "Too many arguments" >&2
    exit 1
fi

command -v lua5.1 >/dev/null 2>&1 || { echo "lua5.1 is required" >&2; exit 1; }
command -v luac5.1 >/dev/null 2>&1 || { echo "luac5.1 is required" >&2; exit 1; }

RUNTIMES=("lua5.1")
if command -v luajit >/dev/null 2>&1; then
    RUNTIMES+=("luajit")
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export E2E_COMPILE_DIR="$TMP_DIR/cache"
mkdir -p "$E2E_COMPILE_DIR"

echo "=== Syntax Check (luac5.1 -p) ==="
SYNTAX_FAILED=0
for f in "$SCRIPT_DIR"/lib/*.lua "$SCRIPT_DIR"/*.lua; do
    if luac5.1 -p "$f"; then
        echo "[PASS] luac5.1 -p $(basename "$f")"
    else
        echo "[FAIL] luac5.1 -p $(basename "$f")"
        SYNTAX_FAILED=$((SYNTAX_FAILED + 1))
    fi
done
if [ "$SYNTAX_FAILED" -ne 0 ]; then
    echo "Syntax check failed ($SYNTAX_FAILED file(s))." >&2
    exit 1
fi

if ! command -v luau >/dev/null 2>&1; then
    echo "[SKIP] luau: executable not installed; Luau transpilation verified via azure_obf.lua -> lua5.1/luajit"
fi

SUITES=()
case "$MODE" in
    tiers)
        SUITES=("tier1_features.lua" "tier2_boundaries.lua" "tier3_pairwise.lua" "tier4_workloads.lua")
        ;;
    r1)
        SUITES=("trap_harness.lua")
        ;;
    r2)
        SUITES=("hardening_eval.lua")
        ;;
    all)
        SUITES=("tier1_features.lua" "tier2_boundaries.lua" "tier3_pairwise.lua" "tier4_workloads.lua" "trap_harness.lua" "hardening_eval.lua")
        ;;
esac

TOTAL_RUNS=0
FAILED_RUNS=0
SUMMARY_LINES=()

cd "$REPO_ROOT" || exit 1

for suite_file in "${SUITES[@]}"; do
    for rt in "${RUNTIMES[@]}"; do
        TOTAL_RUNS=$((TOTAL_RUNS + 1))
        echo ""
        echo "=== Running $suite_file on $rt ==="
        if "$rt" "$SCRIPT_DIR/$suite_file" --compile-dir "$E2E_COMPILE_DIR"; then
            SUMMARY_LINES+=("PASS | $suite_file | $rt")
        else
            FAILED_RUNS=$((FAILED_RUNS + 1))
            SUMMARY_LINES+=("FAIL | $suite_file | $rt")
        fi
    done
done

echo ""
echo "================ E2E RUN SUMMARY ================"
for line in "${SUMMARY_LINES[@]}"; do
    echo "  $line"
done
echo "Total suite/runtime runs: $TOTAL_RUNS, Passed: $((TOTAL_RUNS - FAILED_RUNS)), Failed: $FAILED_RUNS"
echo "================================================="

[ "$FAILED_RUNS" -eq 0 ]
