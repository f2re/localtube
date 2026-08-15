#!/usr/bin/env python3
from pathlib import Path


def replace(path, old, new, count=-1):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'pattern not found in {path}: {old[:120]!r}')
    p.write_text(text.replace(old, new, count), encoding='utf-8')


def write(path, text):
    Path(path).write_text(text, encoding='utf-8')


# Version bump.
write('app/VERSION', '1.4.3\n')
replace('app/server.ts', '// LocalTube 1.4.2 — dependency-free cross-platform Deno backend.', '// LocalTube 1.4.3 — dependency-free cross-platform Deno backend.')
replace('installer/install.sh', '# LocalTube 1.4.2 macOS installer.', '# LocalTube 1.4.3 macOS installer.')
replace('installer/install.sh', "say 'LocalTube 1.4.2 — production installer'", "say 'LocalTube 1.4.3 — production installer'")
replace('app/scripts/runtime_common.sh', 'LocalTube-bootstrap/1.4.2', 'LocalTube-bootstrap/1.4.3')

# External downloads must not silently consume ~/.curlrc. Explicit environment proxy
# variables still work on platforms/install paths where they are intentionally preserved.
p = Path('app/scripts/runtime_common.sh')
text = p.read_text(encoding='utf-8')
text = text.replace('"$_lt_curl" --fail', '"$_lt_curl" -q --fail')
p.write_text(text, encoding='utf-8')

# macOS installer: sterile curl first, raw HTTP over nc as an independent loopback
# fallback. Preserve response/error details instead of hiding them behind curl --fail.
p = Path('installer/install.sh')
text = p.read_text(encoding='utf-8')
start = text.index("LAST_HEALTH_JSON=''\nhealth() {")
end = text.index('\nactive_downloads() {', start)
new = r'''LAST_HEALTH_JSON=''
LAST_HEALTH_RAW=''
LAST_HEALTH_ERROR=''
LAST_HEALTH_TRANSPORT=''

health_via_curl() {
  _port="$(/bin/cat "$DATA/port" 2>/dev/null | /usr/bin/tr -cd '0-9')"
  _token="$(/bin/cat "$DATA/api_token" 2>/dev/null | /usr/bin/tr -d '\r\n')"
  valid_port "$_port" || return 1
  [ -n "$_token" ] || return 1
  _health_json="$(/usr/bin/curl -q --noproxy '*' --http1.1 --silent --show-error \
    --connect-timeout 2 --max-time 12 \
    -H "X-LocalTube-Token: $_token" "http://127.0.0.1:$_port/api/health?refresh=1" 2>&1)"
  _curl_rc=$?
  if [ -n "$_health_json" ]; then LAST_HEALTH_JSON="$_health_json"; fi
  if [ "$_curl_rc" -ne 0 ]; then
    LAST_HEALTH_ERROR="sterile curl exit $_curl_rc: $_health_json"
    return 1
  fi
  printf '%s' "$_health_json" | /usr/bin/grep -q '"ok":true' || return 1
  if printf '%s' "$_health_json" | /usr/bin/grep -q '"ready":true'; then
    LAST_HEALTH_TRANSPORT='curl-direct-loopback'
    return 0
  fi
  return 1
}

health_via_nc() {
  _port="$(/bin/cat "$DATA/port" 2>/dev/null | /usr/bin/tr -cd '0-9')"
  _token="$(/bin/cat "$DATA/api_token" 2>/dev/null | /usr/bin/tr -d '\r\n')"
  valid_port "$_port" || return 1
  [ -n "$_token" ] || return 1
  [ -x /usr/bin/nc ] || return 1
  _health_raw="$(
    /usr/bin/printf 'GET /api/health?refresh=1 HTTP/1.1\r\nHost: 127.0.0.1:%s\r\nX-LocalTube-Token: %s\r\nConnection: close\r\n\r\n' "$_port" "$_token" | \
      /usr/bin/nc -w 15 127.0.0.1 "$_port" 2>&1
  )"
  _nc_rc=$?
  if [ -n "$_health_raw" ]; then LAST_HEALTH_RAW="$_health_raw"; fi
  if [ "$_nc_rc" -ne 0 ]; then
    LAST_HEALTH_ERROR="nc loopback exit $_nc_rc"
    return 1
  fi
  printf '%s' "$_health_raw" | /usr/bin/grep -Eq 'HTTP/1\.[01] 200' || return 1
  if printf '%s' "$_health_raw" | /usr/bin/grep -q '"ready":true'; then
    LAST_HEALTH_TRANSPORT='raw-http-loopback'
    return 0
  fi
  return 1
}

health() {
  health_via_curl && return 0
  health_via_nc && return 0
  return 1
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
  say "transport: ${LAST_HEALTH_TRANSPORT:-none}"
  if [ -n "$LAST_HEALTH_ERROR" ]; then say "last transport error: $LAST_HEALTH_ERROR"; fi
  if [ -n "$LAST_HEALTH_JSON" ]; then printf '%s\n' "$LAST_HEALTH_JSON"; else say '(sterile curl не вернул JSON)'; fi
  if [ -n "$LAST_HEALTH_RAW" ]; then
    say '--- raw loopback HTTP (tail) ---'
    printf '%s\n' "$LAST_HEALTH_RAW" | /usr/bin/tail -n 20
  fi
  if [ -f "$HOME/.curlrc" ]; then say '~/.curlrc: present (LocalTube loopback checks ignore it with curl -q)'; fi
  say '--- launchd state ---'
  /bin/launchctl print "$DOMAIN/$LABEL" 2>&1 | /usr/bin/tail -n 80 || true
  say '--- direct runtime checks ---'
  if [ -x "$RUNTIME/deno" ]; then "$RUNTIME/deno" --version 2>&1 | /usr/bin/head -n 3 || true; else say 'deno: missing'; fi
  if [ -x "$RUNTIME/yt-dlp" ]; then "$RUNTIME/yt-dlp" --version 2>&1 | /usr/bin/head -n 3 || true; else say 'yt-dlp: missing'; fi
  if [ -x "$RUNTIME/ffmpeg" ]; then "$RUNTIME/ffmpeg" -version 2>&1 | /usr/bin/head -n 3 || true; else say 'ffmpeg: missing'; fi
  if [ -x "$RUNTIME/ffprobe" ]; then "$RUNTIME/ffprobe" -version 2>&1 | /usr/bin/head -n 3 || true; else say 'ffprobe: missing'; fi
}
'''
text = text[:start] + new + text[end:]
text = text.replace(
    "DIAG_JSON=\"$(/usr/bin/curl --fail --silent --max-time 75 -H 'Content-Type: application/json'",
    "DIAG_JSON=\"$(/usr/bin/curl -q --noproxy '*' --http1.1 --fail --silent --max-time 75 -H 'Content-Type: application/json'",
)
text = text.replace("say '      runtime: ready'", "say \"      runtime: ready via ${LAST_HEALTH_TRANSPORT:-loopback}\"")
p.write_text(text, encoding='utf-8')

# Shared service helpers.
p = Path('app/scripts/service_common.sh')
text = p.read_text(encoding='utf-8')
text = text.replace('/usr/bin/curl --fail --silent --show-error --max-time 3', "/usr/bin/curl -q --noproxy '*' --http1.1 --fail --silent --show-error --max-time 3")
text = text.replace('/usr/bin/curl --fail --silent --max-time 4', "/usr/bin/curl -q --noproxy '*' --http1.1 --fail --silent --max-time 4")
p.write_text(text, encoding='utf-8')

# Source-checkout .app launcher health.
p = Path('INSTALL.command')
text = p.read_text(encoding='utf-8')
text = text.replace('/usr/bin/curl --fail --silent --max-time 3', "/usr/bin/curl -q --noproxy '*' --http1.1 --fail --silent --max-time 3")
p.write_text(text, encoding='utf-8')

# macOS controls.
p = Path('control/START.command')
text = p.read_text(encoding='utf-8').replace('/usr/bin/curl -fsS --max-time 2', "/usr/bin/curl -q --noproxy '*' --http1.1 -fsS --max-time 2")
p.write_text(text, encoding='utf-8')

p = Path('control/DIAGNOSE.command')
text = p.read_text(encoding='utf-8')
text = text.replace('/usr/bin/curl -sS --max-time 5', "/usr/bin/curl -q --noproxy '*' --http1.1 -sS --max-time 5")
text = text.replace('/usr/bin/curl -sS --max-time 75', "/usr/bin/curl -q --noproxy '*' --http1.1 -sS --max-time 75")
marker = "  printf '%s\\n' '--- authenticated local health ---'\n"
text = text.replace(marker, "  printf '%s\\n' '--- authenticated local health (sterile loopback transport) ---'\n  if [ -f \"$HOME/.curlrc\" ]; then printf '%s\\n' '~/.curlrc: present; intentionally ignored by LocalTube loopback requests'; fi\n")
p.write_text(text, encoding='utf-8')

# Linux local control.
p = Path('control/linux/localtube')
text = p.read_text(encoding='utf-8').replace('curl -fsS', "curl -q --noproxy '*' --http1.1 -fsS")
p.write_text(text, encoding='utf-8')

# macOS integration: poison ~/.curlrc after runtime download. All local API calls must
# remain successful, reproducing the class of failure reported from macOS 13 Intel.
p = Path('scripts/ci_macos_integration.sh')
text = p.read_text(encoding='utf-8')
text = text.replace('/usr/bin/curl -fsS', "/usr/bin/curl -q --noproxy '*' --http1.1 -fsS")
needle = "echo '[macOS 4/7] start production-permission server'\n"
hostile = r'''echo '[macOS curl] hostile ~/.curlrc isolation test'
CURLRC_BACKUP="$WORK/original.curlrc"
CURLRC_HAD_ORIGINAL=0
if [ -f "$HOME/.curlrc" ]; then
  /bin/cp "$HOME/.curlrc" "$CURLRC_BACKUP"
  CURLRC_HAD_ORIGINAL=1
fi
/bin/cat > "$HOME/.curlrc" <<'CURLRC'
proxy = "http://127.0.0.1:9"
header = "Host: hostile.invalid"
connect-timeout = 1
CURLRC

'''
if needle not in text:
    raise SystemExit('macOS integration insertion point not found')
text = text.replace(needle, hostile + needle, 1)
old_cleanup = '''cleanup() {
  if [ -n "$PID" ]; then /bin/kill "$PID" >/dev/null 2>&1 || true; fi
  /bin/rm -rf "$WORK" >/dev/null 2>&1 || true
}'''
new_cleanup = '''cleanup() {
  if [ -n "$PID" ]; then /bin/kill "$PID" >/dev/null 2>&1 || true; fi
  if [ "${CURLRC_HAD_ORIGINAL:-0}" -eq 1 ] && [ -f "${CURLRC_BACKUP:-}" ]; then
    /bin/cp "$CURLRC_BACKUP" "$HOME/.curlrc"
  else
    /bin/rm -f "$HOME/.curlrc"
  fi
  /bin/rm -rf "$WORK" >/dev/null 2>&1 || true
}'''
if old_cleanup not in text:
    raise SystemExit('macOS cleanup block not found')
text = text.replace(old_cleanup, new_cleanup, 1)
p.write_text(text, encoding='utf-8')

# Static regression guard.
write('scripts/check_loopback_transport.py', r'''#!/usr/bin/env python3
from pathlib import Path

checks = {
    'installer/install.sh': ["/usr/bin/curl -q --noproxy '*' --http1.1", '/usr/bin/nc -w 15 127.0.0.1'],
    'INSTALL.command': ["/usr/bin/curl -q --noproxy '*' --http1.1"],
    'app/scripts/service_common.sh': ["/usr/bin/curl -q --noproxy '*' --http1.1"],
    'control/START.command': ["/usr/bin/curl -q --noproxy '*' --http1.1"],
    'control/DIAGNOSE.command': ["/usr/bin/curl -q --noproxy '*' --http1.1"],
    'control/linux/localtube': ["curl -q --noproxy '*' --http1.1"],
    'scripts/ci_macos_integration.sh': ["proxy = \"http://127.0.0.1:9\"", "Host: hostile.invalid", "/usr/bin/curl -q --noproxy '*' --http1.1"],
}
errors=[]
for path, needles in checks.items():
    text=Path(path).read_text(encoding='utf-8')
    for needle in needles:
        if needle not in text:
            errors.append(f'{path}: missing {needle!r}')

runtime=Path('app/scripts/runtime_common.sh').read_text(encoding='utf-8')
if '"$_lt_curl" --fail' in runtime:
    errors.append('runtime_common.sh: network curl still reads default curlrc')
if '"$_lt_curl" -q --fail' not in runtime:
    errors.append('runtime_common.sh: expected -q before bootstrap curl options')

installer=Path('installer/install.sh').read_text(encoding='utf-8')
if "LAST_HEALTH_TRANSPORT='raw-http-loopback'" not in installer:
    errors.append('installer: raw nc loopback fallback missing')
if "sterile curl exit" not in installer:
    errors.append('installer: curl exit diagnostics missing')

if errors:
    raise SystemExit('\n'.join(errors))
print('loopback HTTP isolation guard: OK')
''')

p = Path('scripts/test.sh')
text = p.read_text(encoding='utf-8')
anchor = "python3 scripts/check_health_startup.py\n"
if anchor not in text:
    raise SystemExit('test.sh health anchor not found')
text = text.replace(anchor, anchor + "echo '[loopback] curlrc/proxy isolation regression'\npython3 scripts/check_loopback_transport.py\n", 1)
p.write_text(text, encoding='utf-8')

# Changelog + README.
p = Path('CHANGELOG.md')
text = p.read_text(encoding='utf-8')
entry = '''## 1.4.3 — 2026-08-15

- локальные health/API-запросы больше не зависят от `~/.curlrc`: `curl -q` отключает пользовательский config, а `--noproxy '*'` гарантирует прямой loopback;
- macOS installer имеет независимый raw-HTTP fallback через `/usr/bin/nc`, поэтому сбой/настройка curl больше не вызывает ложный rollback рабочего LaunchAgent;
- при ошибке health печатаются transport, curl exit/body и raw HTTP ответ, а `--fail` больше не скрывает 403/500 во время диагностики;
- то же правило применено к macOS launcher/controls, shared service helpers и Linux control CLI;
- macOS CI теперь намеренно создаёт враждебный `~/.curlrc` с proxy и подменой Host и проверяет, что LocalTube продолжает работать.

'''
text = text.replace('# 🗒️ Changelog\n\n', '# 🗒️ Changelog\n\n' + entry, 1)
p.write_text(text, encoding='utf-8')

p = Path('README.md')
text = p.read_text(encoding='utf-8')
anchor = '### Устойчивость bootstrap к сетевым сбоям\n'
insert = '''### Изоляция локального API от proxy и `.curlrc`

Запросы LocalTube к собственному API на `127.0.0.1` всегда выполняются напрямую: пользовательский `~/.curlrc` отключается (`curl -q`), а proxy обходится (`--noproxy '*'`). На macOS установщик дополнительно умеет проверить health через сырой HTTP поверх системного `nc`, поэтому локальная конфигурация curl не может сама по себе сорвать установку. Внешние загрузки runtime при этом остаются отдельным транспортным контуром.

'''
if anchor in text:
    text = text.replace(anchor, insert + anchor, 1)
else:
    text += '\n\n' + insert
p.write_text(text, encoding='utf-8')
