#!/usr/bin/env python3
from pathlib import Path
errors=[]
server=Path('app/server.ts').read_text()
run=Path('app/scripts/run_server.sh').read_text()
installer=Path('installer/install.sh').read_text()
checks=[
 ('backend loopback bind', "const HOST = '127.0.0.1'" in server),
 ('API token gate', 'apiAllowed(req, token)' in server),
 ('Host validation', 'hostOk(req)' in server),
 ('Origin validation', "req.headers.get('origin')" in server),
 ('YouTube URL allowlist', 'youtubeUrlKind' in server and 'youtube.com' in server),
 ('yt-dlp ignores ambient config', "'--ignore-config'" in server),
 ('no shell command interpolation', 'Deno.Command(cmd' in server and 'shell:' not in server),
 ('Deno no blanket -A in launchd', ' -A ' not in run and '--allow-run=' in run),
 ('clean shell launch', '--noprofile' in installer and '--norc' in installer),
 ('transaction rollback', 'rollback()' in installer and 'TX_ACTIVE' in installer),
 ('package hash validation', 'MANIFEST.sha256' in installer),
]
for name,ok in checks:
    if not ok: errors.append(name)
if errors:
    print('FAILED: '+', '.join(errors)); raise SystemExit(1)
print('static security/audit regression checks: OK')
