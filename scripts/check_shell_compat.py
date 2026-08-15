#!/usr/bin/env python3
from pathlib import Path
files=[Path('installer/install.sh'),*Path('app/scripts').glob('*.sh')]
# Features absent from Apple's Bash 3.2, accidental user-shell sourcing, and
# library-level option mutations that can silently weaken callers using `set -e`.
forbidden={
    'mapfile':'bash >=4',
    'readarray':'bash >=4',
    'declare -A':'associative arrays need bash >=4',
    '${!':'indirect expansions are avoided for portability',
    'source ~/.':'user profile sourcing',
    'source "$HOME/.':'user profile sourcing',
    'set +e':'must not disable caller errexit globally',
}
errors=[]
for p in files:
    raw=p.read_text()
    s='\n'.join(line for line in raw.splitlines() if not line.lstrip().startswith('#'))
    for token,why in forbidden.items():
        if token in s: errors.append(f'{p}: {token!r}: {why}')
    if not raw.startswith('#!/bin/bash'): errors.append(f'{p}: expected /bin/bash shebang')
if errors:
    print('\n'.join(errors)); raise SystemExit(1)
print('bash 3.2 compatibility/shell-option guard: OK')
