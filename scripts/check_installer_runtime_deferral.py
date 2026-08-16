#!/usr/bin/env python3
from pathlib import Path
s = Path('installer/install.sh').read_text(encoding='utf-8')
checks = {
    'runtime replacement flag': 'REPLACE_RUNTIME=1' in s,
    'authoritative API gate': 'if active_downloads; then' in s,
    'compatibility test': 'current_runtime_compatible()' in s,
    'runtime defer path': "REPLACE_RUNTIME=0" in s and 'consider_runtime_deferral()' in s,
    'conditional runtime backup': 'if [ "$REPLACE_RUNTIME" -eq 1 ] && [ -d "$RUNTIME" ]' in s,
    'conditional runtime activation': 'if [ "$REPLACE_RUNTIME" -eq 1 ]; then\n  NEW_RUNTIME=1;' in s,
    'preflight before bootstrap': s.find('consider_runtime_deferral') < s.find('lt_install_runtime "$STAGE/runtime"'),
    'no old unconditional blocker': 'Обнаружен активный процесс yt-dlp/FFmpeg предыдущего runtime' not in s,
    'brand assets packaged': all(x in s for x in ['static/brand.css','static/brand/favicon.svg','static/brand/favicon.ico','static/brand/icon-192.png']),
}
bad = [name for name, ok in checks.items() if not ok]
if bad:
    raise SystemExit('installer runtime-deferral regression: ' + ', '.join(bad))
print('installer active-runtime deferral guard: OK')
