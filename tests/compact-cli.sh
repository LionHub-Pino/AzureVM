#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
python3 - <<'PY'
import pathlib, subprocess, tempfile
with tempfile.TemporaryDirectory() as d:
    source = pathlib.Path(d) / 'input.lua'
    output = pathlib.Path(d) / 'output.lua'
    source.write_text('print("compact-cli-ok")')
    for preset in ['Luraph', 'Luraph14', 'Luraph15', 'AzureGod', 'AzureGod15', 'AzureGodUltra']:
        subprocess.run(['lua5.1', 'azure_obf.lua', str(source), '--preset', preset, '--compact', '--seed', '12345', '-o', str(output)], check=True, stdout=subprocess.DEVNULL)
        data = output.read_bytes()
        assert b'\n' not in data and b'\r' not in data, preset
        assert subprocess.check_output(['lua5.1', str(output)]) == b'compact-cli-ok\n', preset
print('compact CLI: ok')
PY
