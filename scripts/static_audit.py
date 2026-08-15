#!/usr/bin/env python3
from pathlib import Path
errors=[]
server=Path('app/server.ts').read_text()
run_unix=Path('app/scripts/run_server.sh').read_text()
run_win=Path('app/scripts/run_server.ps1').read_text()
installer=Path('installer/install.sh').read_text()
checks=[
 ('backend loopback bind', "const HOST = '127.0.0.1'" in server),
 ('API token gate', 'apiAllowed(req, token)' in server),
 ('Host validation', 'hostOk(req)' in server),
 ('Origin validation', "req.headers.get('origin')" in server),
 ('YouTube URL allowlist', 'youtubeUrlKind' in server and 'youtube.com' in server),
 ('yt-dlp ignores ambient config', "'--ignore-config'" in server),
 ('no shell interpolation in backend', 'Deno.Command(cmd' in server and 'shell:' not in server),
 ('Unix restricted Deno subprocesses', ' -A ' not in run_unix and '--allow-run=' in run_unix),
 ('Windows restricted Deno subprocesses', "'run','--no-config','--no-prompt'" in run_win and '--allow-run=' in run_win),
 ('clean macOS shell launch', '--noprofile' in installer and '--norc' in installer),
 ('macOS transaction rollback', 'rollback()' in installer and 'TX_ACTIVE' in installer),
 ('package hash validation', 'MANIFEST.sha256' in installer),
 ('cross-platform runtime', 'Deno.build' in server and 'runtime_windows.ps1' in Path('installer/install-windows.ps1').read_text()),
]
for name,ok in checks:
    if not ok: errors.append(name)
if errors:
    print('FAILED: '+', '.join(errors)); raise SystemExit(1)
print('static security/audit regression checks: OK')
