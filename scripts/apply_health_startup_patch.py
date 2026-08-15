#!/usr/bin/env python3
from pathlib import Path


def replace(path, old, new, count=1):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'pattern not found in {path}: {old!r}')
    p.write_text(text.replace(old, new, count), encoding='utf-8')


Path('app/VERSION').write_text('1.4.2\n', encoding='utf-8')
replace('app/server.ts', '// LocalTube 1.4.1 — dependency-free cross-platform Deno backend.', '// LocalTube 1.4.2 — dependency-free cross-platform Deno backend.')
replace('installer/install.sh', '# LocalTube 1.4.1 macOS installer.', '# LocalTube 1.4.2 macOS installer.')
replace("installer/install.sh", "say 'LocalTube 1.4.1 — production installer'", "say 'LocalTube 1.4.2 — production installer'")
replace('app/scripts/runtime_common.sh', 'LocalTube-bootstrap/1.4.1', 'LocalTube-bootstrap/1.4.2')

replace(
    'app/server.ts',
    "async function runtimeStatus(force = false): Promise<Json> {\n  if (!force && runtimeStatusCache && Date.now() - runtimeStatusCache.at < 30_000) return runtimeStatusCache.value;",
    "async function runtimeStatus(force = false): Promise<Json> {\n  const cacheTtl = runtimeStatusCache?.value.ready === true ? 30_000 : 1_000;\n  if (!force && runtimeStatusCache && Date.now() - runtimeStatusCache.at < cacheTtl) return runtimeStatusCache.value;",
)
replace(
    'app/server.ts',
    "if (req.method === 'GET' && url.pathname === '/api/health') return jsonResponse({ ok: true, runtime: await runtimeStatus() });",
    "if (req.method === 'GET' && url.pathname === '/api/health') return jsonResponse({ ok: true, runtime: await runtimeStatus(url.searchParams.get('refresh') === '1') });",
)
replace('app/server.ts', 'const local = await runtimeStatus();\n  const result: Json = { local, youtube:', 'const local = await runtimeStatus(true);\n  const result: Json = { local, youtube:')

old_health = '''health() {
  _port="$(/bin/cat "$DATA/port" 2>/dev/null | /usr/bin/tr -cd '0-9')"
  _token="$(/bin/cat "$DATA/api_token" 2>/dev/null | /usr/bin/tr -d '\\r\\n')"
  valid_port "$_port" || return 1
  [ -n "$_token" ] || return 1
  /usr/bin/curl --fail --silent --show-error --max-time 3 \\
    -H "X-LocalTube-Token: $_token" "http://127.0.0.1:$_port/api/health" 2>/dev/null | /usr/bin/grep -q '"ok":true'
}

wait_health() {
  _i=0
  while [ "$_i" -lt 35 ]; do health && return 0; /bin/sleep 1; _i=$((_i + 1)); done
  return 1
}
'''
new_health = '''LAST_HEALTH_JSON=''
health() {
  _port="$(/bin/cat "$DATA/port" 2>/dev/null | /usr/bin/tr -cd '0-9')"
  _token="$(/bin/cat "$DATA/api_token" 2>/dev/null | /usr/bin/tr -d '\\r\\n')"
  valid_port "$_port" || return 1
  [ -n "$_token" ] || return 1
  _health_json="$(/usr/bin/curl --fail --silent --show-error --max-time 12 \\
    -H "X-LocalTube-Token: $_token" "http://127.0.0.1:$_port/api/health?refresh=1" 2>/dev/null)" || return 1
  [ -n "$_health_json" ] && LAST_HEALTH_JSON="$_health_json"
  printf '%s' "$_health_json" | /usr/bin/grep -q '"ok":true' || return 1
  printf '%s' "$_health_json" | /usr/bin/grep -q '"ready":true'
}

wait_health() {
  _i=0
  while [ "$_i" -lt 75 ]; do
    health && return 0
    /bin/sleep 1
    _i=$((_i + 1))
  done
  return 1
}

print_health_diagnostics() {
  say '--- runtime health ---'
  if [ -n "$LAST_HEALTH_JSON" ]; then printf '%s\\n' "$LAST_HEALTH_JSON"; else say '(health endpoint не вернул JSON)'; fi
  say '--- launchd state ---'
  /bin/launchctl print "$DOMAIN/$LABEL" 2>&1 | /usr/bin/tail -n 80 || true
  say '--- direct runtime checks ---'
  if [ -x "$RUNTIME/deno" ]; then "$RUNTIME/deno" --version 2>&1 | /usr/bin/head -n 3 || true; else say 'deno: missing'; fi
  if [ -x "$RUNTIME/yt-dlp" ]; then "$RUNTIME/yt-dlp" --version 2>&1 | /usr/bin/head -n 3 || true; else say 'yt-dlp: missing'; fi
  if [ -x "$RUNTIME/ffmpeg" ]; then "$RUNTIME/ffmpeg" -version 2>&1 | /usr/bin/head -n 3 || true; else say 'ffmpeg: missing'; fi
  if [ -x "$RUNTIME/ffprobe" ]; then "$RUNTIME/ffprobe" -version 2>&1 | /usr/bin/head -n 3 || true; else say 'ffprobe: missing'; fi
}
'''
replace('installer/install.sh', old_health, new_health)

old_final = '''say '[7/8] Проверяю authenticated HTTP health-check…'
gui_notify 'Запускаю локальный сервис и проверяю его состояние…'
if ! wait_health; then
  if [ -f "$LOGS/stderr.log" ]; then say '--- последние строки stderr ---'; /usr/bin/tail -n 40 "$LOGS/stderr.log" >&2 || true; fi
  fail 'LocalTube не ответил за 35 секунд.'
fi
TOKEN="$(/bin/cat "$DATA/api_token" 2>/dev/null | /usr/bin/tr -d '\\r\\n')"
HEALTH_JSON="$(/usr/bin/curl --fail --silent --max-time 5 -H "X-LocalTube-Token: $TOKEN" "http://127.0.0.1:$PORT/api/health" 2>/dev/null)" || fail 'Контрольный health-check завершился ошибкой.'
printf '%s' "$HEALTH_JSON" | /usr/bin/grep -q '"ready":true' || fail 'Сервис запущен, но автономное окружение не готово.'
'''
new_final = '''say '[7/8] Проверяю authenticated HTTP health-check и готовность runtime…'
gui_notify 'Запускаю локальный сервис и проверяю его состояние…'
if ! wait_health; then
  print_health_diagnostics
  if [ -f "$LOGS/stderr.log" ]; then say '--- последние строки stderr ---'; /usr/bin/tail -n 80 "$LOGS/stderr.log" >&2 || true; fi
  fail 'LocalTube не вышел в состояние runtime.ready=true за 75 секунд. Диагностика напечатана выше; предыдущая версия восстановлена.'
fi
TOKEN="$(/bin/cat "$DATA/api_token" 2>/dev/null | /usr/bin/tr -d '\\r\\n')"
HEALTH_JSON="$LAST_HEALTH_JSON"
say '      runtime: ready'
'''
replace('installer/install.sh', old_final, new_final)

check = Path('scripts/check_health_startup.py')
check.write_text(r'''#!/usr/bin/env python3
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
''', encoding='utf-8')

test = Path('scripts/test.sh')
text = test.read_text(encoding='utf-8')
marker = "echo '[4/11] Unix runtime destination guard'\n"
extra = "echo '[health] startup readiness race regression'\npython3 scripts/check_health_startup.py\n\n"
if 'startup readiness race regression' not in text:
    if marker not in text:
        raise SystemExit('scripts/test.sh insertion marker not found')
    test.write_text(text.replace(marker, extra + marker, 1), encoding='utf-8')

changelog = Path('CHANGELOG.md')
text = changelog.read_text(encoding='utf-8')
marker = '# 🗒️ Changelog\n\n'
section = '''## 1.4.2 — 2026-08-15\n\n- исправлена гонка macOS LaunchAgent startup: installer больше не принимает `ok:true` за готовность и ждёт именно `runtime.ready:true`;\n- отрицательный runtime status больше не кэшируется на 30 секунд — transient cold-start повторно проверяется через 1 секунду;\n- `/api/health?refresh=1` принудительно перепроверяет yt-dlp/FFmpeg/FFprobe во время установки;\n- окно запуска увеличено до 75 секунд для старых Intel Mac и первого запуска бинарников после установки;\n- при реальном сбое installer печатает health JSON, состояние launchd, прямые версии Deno/yt-dlp/FFmpeg/FFprobe и stderr до rollback;\n- добавлен regression guard против возврата one-shot health-check из 1.4.1.\n\n'''
if '## 1.4.2 — 2026-08-15' not in text:
    if marker not in text:
        raise SystemExit('CHANGELOG marker not found')
    changelog.write_text(text.replace(marker, marker + section, 1), encoding='utf-8')
