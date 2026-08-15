#!/usr/bin/env python3
from pathlib import Path

checks = {
    'installer/install.sh': ["/usr/bin/curl -q --noproxy '*' --http1.1", '/usr/bin/nc -w 15 127.0.0.1'],
    'INSTALL.command': ["/usr/bin/curl -q --noproxy '*' --http1.1"],
    'app/scripts/service_common.sh': ["/usr/bin/curl -q --noproxy '*' --http1.1"],
    'control/START.command': ["/usr/bin/curl -q --noproxy '*' --http1.1"],
    'control/DIAGNOSE.command': ["/usr/bin/curl -q --noproxy '*' --http1.1"],
    'control/linux/localtube': ["curl -q --noproxy '*' --http1.1"],
    'scripts/ci_macos_integration.sh': [
        'proxy = "http://127.0.0.1:9"',
        'Host: hostile.invalid',
        "/usr/bin/curl -q --noproxy '*' --http1.1",
    ],
}
errors=[]
for path, needles in checks.items():
    text=Path(path).read_text(encoding='utf-8')
    for needle in needles:
        if needle not in text:
            errors.append(f'{path}: missing {needle!r}')
    # These files use curl only for LocalTube's own loopback API. Every invocation must
    # start with -q and bypass proxies. This prevents a future helper from silently
    # reintroducing ~/.curlrc/proxy dependence in a different endpoint.
    for lineno, line in enumerate(text.splitlines(), 1):
        if 'curl ' in line and ('/usr/bin/curl' in line or line.lstrip().startswith('curl ')):
            if ' -q ' not in line or "--noproxy '*'" not in line:
                errors.append(f'{path}:{lineno}: non-sterile curl invocation: {line.strip()}')

runtime=Path('app/scripts/runtime_common.sh').read_text(encoding='utf-8')
if '"$_lt_curl" --fail' in runtime:
    errors.append('runtime_common.sh: network curl still reads default curlrc')
if '"$_lt_curl" -q --fail' not in runtime:
    errors.append('runtime_common.sh: expected -q before bootstrap curl options')

installer=Path('installer/install.sh').read_text(encoding='utf-8')
if "LAST_HEALTH_TRANSPORT='raw-http-loopback'" not in installer:
    errors.append('installer: raw nc loopback fallback missing')
if 'sterile curl exit' not in installer:
    errors.append('installer: curl exit diagnostics missing')
if 'health_via_curl && return 0\n  health_via_nc && return 0' not in installer:
    errors.append('installer: health must fall back from sterile curl to raw loopback HTTP')

if errors:
    raise SystemExit('\n'.join(errors))
print('loopback HTTP isolation guard: OK')
