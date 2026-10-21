#!/usr/bin/env bash
# A source and VM that both fail must never be reported as a semantic pass.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
cat > "$tmp/bin/lua5.1" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    */azure_obf.lua) exit 0 ;;
    *) exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/lua5.1"
if PATH="$tmp/bin:$PATH" bash "$repo/tests/verify-vm.sh" >"$tmp/log" 2>&1; then
    echo 'FAIL: harness accepted matching nonzero exits' >&2
    exit 1
fi
grep -q 'FAIL.*source=1, build=0, VM=1' "$tmp/log"
printf 'harness validation: ok\n'
