#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
python3 - <<'PY'
import pathlib,shutil,subprocess,tempfile
with tempfile.TemporaryDirectory(prefix='azurevm-retry-cli-') as directory:
    root=pathlib.Path(directory)
    source,output=root/'input.lua',root/'protected.lua'
    source.write_text('attempts=(attempts or 0)+1; print(attempts); if attempts<4 then error("again",0) end')
    def build(preset,flags):
        output.unlink(missing_ok=True)
        return subprocess.run(['lua5.1','azure_obf.lua',str(source),'--preset',preset,
            '--compact','--seed','12345','-o',str(output),*flags],capture_output=True)
    for preset,flags,status,expected in [
        ('AzureGodUltra',[],0,b'1\n2\n3\n4\n'),
        ('AzureGodUltra',['--retry-count=3'],0,b'1\n2\n3\n4\n'),
        ('AzureGodUltra',['--retry-count','2'],1,b'1\n2\n3\n'),
        ('AzureGodUltra',['--retry-count=0'],1,b'1\n'),
        ('Luraph',['--retry-count=3'],0,b'1\n2\n3\n4\n'),
    ]:
        result=build(preset,flags)
        assert result.returncode==0,result.stderr
        data=output.read_bytes()
        assert b'\r' not in data and b'\n' not in data
        for runtime in ['lua5.1','luajit','luau']:
            if not shutil.which(runtime):
                continue
            run=subprocess.run([runtime,str(output)],capture_output=True,timeout=30)
            assert (run.returncode==0)==(status==0),(runtime,flags,run.stderr)
            assert run.stdout==expected,(runtime,flags,run.stdout,expected)
    for flags in [
        ['--retry-count'],['--retry-count='],['--retry-count=-1'],
        ['--retry-count=101'],['--retry-count=1.5'],['--retry-count=nan'],
        ['--retry-count=inf'],['--retry-count=garbage'],
    ]:
        result=build('AzureGodUltra',flags)
        assert result.returncode!=0 and not output.exists(),flags
print('retry CLI: defaults, overrides, compact output, side effects and validation: ok')
PY
