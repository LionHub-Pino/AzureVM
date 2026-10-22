#!/usr/bin/env python3
"""Compare Ultra compact output to Lua 5.1 on each installed named runtime."""
import hashlib
import pathlib
import shutil
import subprocess
import tempfile

REPO = pathlib.Path(__file__).resolve().parent.parent
EXCLUDED = {
    "false-constants.lua", "payload-integrity.lua", "seed-behavior.lua",
    "per-prototype-layout.lua", "chained-layout.lua",
}
RUNTIMES = [name for name in ("lua5.1", "luajit", "luau") if shutil.which(name)]
if "lua5.1" not in RUNTIMES:
    raise SystemExit("Lua 5.1 is required to compile and establish the baseline")


def run(command):
    result = subprocess.run(command, cwd=REPO, capture_output=True, timeout=30)
    if result.returncode:
        raise RuntimeError(
            f"{command!r} exited {result.returncode}: "
            f"{result.stderr.decode(errors='replace')}"
        )
    return result.stdout


for runtime in RUNTIMES:
    binary = pathlib.Path(shutil.which(runtime)).resolve()
    digest = hashlib.sha256(binary.read_bytes()).hexdigest()
    print(f"Runtime {runtime}: {binary}, sha256={digest}", flush=True)

passed = {name: 0 for name in RUNTIMES}
with tempfile.TemporaryDirectory(prefix="azurevm-matrix-") as directory:
    output = pathlib.Path(directory) / "protected.lua"
    for source in sorted((REPO / "tests").glob("*.lua")):
        if source.name in EXCLUDED:
            continue
        expected = run(["lua5.1", str(source)])
        run([
            "lua5.1", "azure_obf.lua", str(source), "--preset", "AzureGodUltra",
            "--compact", "--seed", "12345", "-o", str(output),
        ])
        data = output.read_bytes()
        if not data or b"\r" in data or b"\n" in data:
            raise AssertionError(f"Not single-line output: {source.name}")
        for runtime in RUNTIMES:
            actual = run([runtime, str(output)])
            if actual != expected:
                raise AssertionError(
                    f"{runtime}/{source.name}: expected {expected!r}, got {actual!r}"
                )
            passed[runtime] += 1
            print(f"PASS {runtime}/{source.name}", flush=True)
for runtime, count in passed.items():
    print(f"{runtime}: {count} passed, 0 failed")
for runtime in ("luajit", "luau"):
    if runtime not in RUNTIMES:
        print(f"SKIP {runtime}: executable not installed; no compatibility claim")
