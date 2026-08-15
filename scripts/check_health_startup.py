#!/usr/bin/env python3
from pathlib import Path
server = Path('app/server.ts').read_text(encoding='utf-8')
installer = Path('installer/install.sh').read_text(encoding='utf-8')
errors = []
if "runtimeStatusCache?.value.ready === true ? 30_000 : 1_000" not in server:
    errors.append('server must use a short TTL for negative runtime readiness')
if "runtimeStatus(url.searchParams.get('refresh') === '1')" not in server:
    errors.append('health endpoint must support a forced runtime refresh')
if "api/health?refresh=1" not in installer:
    errors.append('installer must force fresh runtime probes while waiting')
if '"ready":true' not in installer:
    errors.append('installer health gate must require runtime.ready=true')
if 'while [ "$_i" -lt 75 ]' not in installer:
    errors.append('installer must allow slow Intel/macOS cold starts')
if "Сервис запущен, но автономное окружение не готово." in installer:
    errors.append('one-shot cached-ready failure path must be removed')
if 'print_health_diagnostics' not in installer:
    errors.append('failed startup must print actionable runtime diagnostics')
if errors:
    raise SystemExit('\n'.join(errors))
print('startup readiness race guard: OK')
