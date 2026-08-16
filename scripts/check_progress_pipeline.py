#!/usr/bin/env python3
from pathlib import Path
server=Path('app/server.ts').read_text(encoding='utf-8')
ui=Path('app/static/app.js').read_text(encoding='utf-8')
css=Path('app/static/styles.css').read_text(encoding='utf-8')
build=Path('scripts/build_release.py').read_text(encoding='utf-8')
verify=Path('scripts/verify_release.py').read_text(encoding='utf-8')
errors=[]
for needle in ['progress.downloaded_bytes','progress.total_bytes_estimate','postprocess:__LOCALTUBE_POSTPROCESS__','.localtube-tmp','final_size_bytes','await cleanupJobTemp(j)']:
    if needle not in server: errors.append(f'server missing {needle}')
if 'progress._percent_str' in server: errors.append('server still parses decorative _percent_str')
for needle in ['j.total_bytes','j.final_size_bytes','postprocessing']:
    if needle not in ui: errors.append(f'UI missing {needle}')
if '.job.postprocessing .progress-bar' not in css: errors.append('indeterminate postprocess CSS missing')
for needle in ["ROOT / 'INSTALL.ps1'", "ROOT / 'INSTALL.cmd'", "installer/install-windows.ps1"]:
    if needle not in build: errors.append(f'Windows package builder missing {needle}')
if "prefix + 'INSTALL.cmd'" not in verify: errors.append('Windows verifier does not require INSTALL.cmd')
if errors: raise SystemExit('\n'.join(errors))
print('download progress/temp-file + Windows installer guard: OK')
