#!/usr/bin/env python3
from pathlib import Path


def patch(path: str, old: str, new: str, count: int = 1) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    n = text.count(old)
    if n != count:
        raise SystemExit(f'{path}: expected {count} occurrence(s), found {n}: {old[:100]!r}')
    p.write_text(text.replace(old, new, count), encoding='utf-8')

# Version is intentionally bumped: this release includes the branding merged earlier
# plus the installer/runtime ownership fix.
Path('app/VERSION').write_text('1.4.5\n', encoding='utf-8')
patch('app/server.ts', '// LocalTube 1.4.4 — dependency-free cross-platform Deno backend.', '// LocalTube 1.4.5 — dependency-free cross-platform Deno backend.')
patch('installer/install-windows.ps1', "Write-Host 'LocalTube 1.4.4 — Windows installer'", "Write-Host 'LocalTube 1.4.5 — Windows installer'")

p = Path('installer/install.sh')
s = p.read_text(encoding='utf-8')
s = s.replace('# LocalTube 1.4.4 macOS installer.', '# LocalTube 1.4.5 macOS installer.', 1)
s = s.replace("say 'LocalTube 1.4.4 — production installer'", "say 'LocalTube 1.4.5 — production installer'", 1)
s = s.replace('NEW_PLIST=0\n', "NEW_PLIST=0\nREPLACE_RUNTIME=1\nSERVICE_HEALTHY=0\nRUNTIME_DEFER_REASON=''\n", 1)
old = '''active_runtime_processes() {
  [ -x /usr/bin/pgrep ] || return 1
  /usr/bin/pgrep -f "$RUNTIME/yt-dlp" >/dev/null 2>&1 && return 0
  /usr/bin/pgrep -f "$RUNTIME/ffmpeg" >/dev/null 2>&1 && return 0
  return 1
}
'''
new = '''regex_escape() {
  printf '%s' "$1" | /usr/bin/sed 's/[][(){}.^$*+?|\\\\]/\\\\&/g'
}

runtime_process_pids() {
  [ -x /usr/bin/pgrep ] || return 1
  _yt_re="^$(regex_escape "$RUNTIME/yt-dlp")([[:space:]]|$)"
  _ff_re="^$(regex_escape "$RUNTIME/ffmpeg")([[:space:]]|$)"
  {
    /usr/bin/pgrep -f "$_yt_re" 2>/dev/null || true
    /usr/bin/pgrep -f "$_ff_re" 2>/dev/null || true
  } | /usr/bin/awk 'NF && !seen[$1]++ { print $1 }'
}

active_runtime_processes() {
  [ -n "$(runtime_process_pids)" ]
}

print_runtime_processes() {
  _pids="$(runtime_process_pids)"
  [ -n "$_pids" ] || return 0
  say '--- процессы текущего LocalTube runtime ---'
  for _pid in $_pids; do
    /bin/ps -p "$_pid" -o pid=,ppid=,etime=,command= 2>/dev/null || true
  done
}

current_runtime_compatible() {
  [ -x "$RUNTIME/deno" ] && [ -x "$RUNTIME/yt-dlp" ] && [ -x "$RUNTIME/ffmpeg" ] && [ -x "$RUNTIME/ffprobe" ] || return 1
  /bin/rm -rf "$STAGE/compat" >/dev/null 2>&1 || true
  /bin/mkdir -p "$STAGE/compat" || return 1
  HOME="$HOME" LOCALTUBE_BASE="$STAGE/compat" LOCALTUBE_APP_DIR="$STAGE/app" LOCALTUBE_RUNTIME_DIR="$RUNTIME" \\
    "$RUNTIME/deno" run --no-config -A "$STAGE/app/server.ts" --self-test >/dev/null 2>&1
}

consider_runtime_deferral() {
  active_runtime_processes || return 1
  if [ "$SERVICE_HEALTHY" -ne 1 ]; then
    print_runtime_processes
    fail 'Обнаружен процесс из текущего LocalTube runtime, но локальный API не отвечает. Нельзя безопасно определить владельца процесса; сервис и runtime оставлены без изменений.'
  fi
  if current_runtime_compatible; then
    REPLACE_RUNTIME=0
    RUNTIME_DEFER_REASON='текущий runtime используется отдельным процессом; его обновление отложено'
    warn 'Найдён yt-dlp/FFmpeg из текущего runtime при пустой очереди LocalTube. Текущий runtime совместим с новой версией: обновляю приложение, не перемещая и не прерывая runtime.'
    print_runtime_processes
    return 0
  fi
  print_runtime_processes
  fail 'Текущий runtime занят процессом и не прошёл проверку совместимости с новой версией. Дождитесь завершения процесса и повторите установку.'
}
'''
if old not in s:
    raise SystemExit('installer/install.sh: active_runtime_processes anchor not found')
s = s.replace(old, new, 1)

# Branding assets are now part of the production package contract.
s = s.replace('''  "$PAYLOAD/static/styles.css" \\
  "$PAYLOAD/scripts/runtime_common.sh" \\
''', '''  "$PAYLOAD/static/styles.css" \\
  "$PAYLOAD/static/brand.css" \\
  "$PAYLOAD/static/brand/favicon.svg" \\
  "$PAYLOAD/static/brand/favicon.ico" \\
  "$PAYLOAD/static/brand/icon-192.png" \\
  "$PAYLOAD/scripts/runtime_common.sh" \\
''', 1)

anchor = '''/usr/bin/plutil -lint "$STAGE/LocalTube.app/Contents/Info.plist" >/dev/null 2>&1 || fail 'Info.plist LocalTube.app повреждён.'

say '[2/8] Скачиваю проверенное окружение: Deno, yt-dlp, FFmpeg/FFprobe…'
'''
replacement = '''/usr/bin/plutil -lint "$STAGE/LocalTube.app/Contents/Info.plist" >/dev/null 2>&1 || fail 'Info.plist LocalTube.app повреждён.'

# Decide ownership before any network bootstrap. The running LocalTube API is the
# authoritative source for managed jobs. A stray/manual runtime process must not
# prevent an app-only update when the current runtime is compatible.
if health; then
  SERVICE_HEALTHY=1
  if active_downloads; then
    fail 'Сейчас есть активные загрузки LocalTube. Дождитесь их завершения и повторите установку.'
  fi
  if active_runtime_processes; then consider_runtime_deferral || true; fi
elif active_runtime_processes; then
  SERVICE_HEALTHY=0
  consider_runtime_deferral || true
fi

if [ "$REPLACE_RUNTIME" -eq 1 ]; then
  say '[2/8] Скачиваю проверенное окружение: Deno, yt-dlp, FFmpeg/FFprobe…'
else
  say '[2/8] Сохраняю текущий проверенный runtime: он используется отдельным процессом.'
fi
'''
if anchor not in s:
    raise SystemExit('installer/install.sh: step2 anchor not found')
s = s.replace(anchor, replacement, 1)

old = '''gui_notify 'Скачиваю и проверяю Deno, yt-dlp и FFmpeg…'
. "$STAGE/app/scripts/runtime_common.sh" || fail 'Не удалось загрузить модуль установки окружения.'
LOCALTUBE_BOOTSTRAP_CACHE="$CACHE/bootstrap" LOCALTUBE_EXISTING_RUNTIME="$RUNTIME" lt_install_runtime "$STAGE/runtime" || fail 'Не удалось получить рабочее окружение ни из сети, ни из проверенного кэша, ни из предыдущей установки. Старая версия LocalTube не была остановлена.'

say '[3/8] Выполняю backend self-test на скачанном окружении…'
HOME="$HOME" LOCALTUBE_BASE="$STAGE" LOCALTUBE_APP_DIR="$STAGE/app" LOCALTUBE_RUNTIME_DIR="$STAGE/runtime" \\
  "$STAGE/runtime/deno" run --no-config -A "$STAGE/app/server.ts" --self-test >/dev/null 2>&1 || \\
  fail 'Backend не прошёл self-test. Старая версия LocalTube не была остановлена.'
'''
new = '''. "$STAGE/app/scripts/runtime_common.sh" || fail 'Не удалось загрузить модуль установки окружения.'
if [ "$REPLACE_RUNTIME" -eq 1 ]; then
  gui_notify 'Скачиваю и проверяю Deno, yt-dlp и FFmpeg…'
  LOCALTUBE_BOOTSTRAP_CACHE="$CACHE/bootstrap" LOCALTUBE_EXISTING_RUNTIME="$RUNTIME" lt_install_runtime "$STAGE/runtime" || fail 'Не удалось получить рабочее окружение ни из сети, ни из проверенного кэша, ни из предыдущей установки. Старая версия LocalTube не была остановлена.'
  RUNTIME_FOR_TEST="$STAGE/runtime"
else
  RUNTIME_FOR_TEST="$RUNTIME"
fi

say '[3/8] Выполняю backend self-test на выбранном окружении…'
HOME="$HOME" LOCALTUBE_BASE="$STAGE/selftest" LOCALTUBE_APP_DIR="$STAGE/app" LOCALTUBE_RUNTIME_DIR="$RUNTIME_FOR_TEST" \\
  "$RUNTIME_FOR_TEST/deno" run --no-config -A "$STAGE/app/server.ts" --self-test >/dev/null 2>&1 || \\
  fail 'Backend не прошёл self-test. Старая версия LocalTube не была остановлена.'
'''
if old not in s:
    raise SystemExit('installer/install.sh: runtime install block not found')
s = s.replace(old, new, 1)

old = '''# Safety gate is deliberately BEFORE TX_ACTIVE: discovering an active download must never
# call rollback(), because rollback stops launchd. If the HTTP service is unhealthy, a
# direct process check still protects an in-flight yt-dlp/ffmpeg child.
if health && active_downloads; then
  fail 'Сейчас есть активные загрузки. Дождитесь их завершения и повторите установку.'
fi
# Protect orphaned/maintenance child processes too. A download may still be finishing
# even when launchctl no longer reports the service as loaded; moving the runtime out
# from under such a process can break its later FFmpeg stage.
if active_runtime_processes; then
  fail 'Обнаружен активный процесс yt-dlp/FFmpeg предыдущего runtime. Установка не будет его прерывать; дождитесь завершения и повторите.'
fi
'''
new = '''# Re-check immediately before the transaction to close the race where the user starts
# a download or a manual runtime process while staging is being prepared.
SERVICE_HEALTHY=0
if health; then
  SERVICE_HEALTHY=1
  if active_downloads; then
    fail 'Пока готовилась установка, появилась активная загрузка LocalTube. Дождитесь её завершения и повторите.'
  fi
fi
if [ "$REPLACE_RUNTIME" -eq 1 ] && active_runtime_processes; then
  consider_runtime_deferral || true
fi
'''
if old not in s:
    raise SystemExit('installer/install.sh: old safety gate not found')
s = s.replace(old, new, 1)

s = s.replace('''if [ -d "$APP" ]; then BACKED_APP=1; /bin/mv "$APP" "$BACKUP/app" || fail 'Не удалось подготовить откат backend.'; fi
if [ -d "$RUNTIME" ]; then BACKED_RUNTIME=1; /bin/mv "$RUNTIME" "$BACKUP/runtime" || fail 'Не удалось подготовить откат runtime.'; fi
''', '''if [ -d "$APP" ]; then BACKED_APP=1; /bin/mv "$APP" "$BACKUP/app" || fail 'Не удалось подготовить откат backend.'; fi
if [ "$REPLACE_RUNTIME" -eq 1 ] && [ -d "$RUNTIME" ]; then BACKED_RUNTIME=1; /bin/mv "$RUNTIME" "$BACKUP/runtime" || fail 'Не удалось подготовить откат runtime.'; fi
''', 1)
s = s.replace('''NEW_APP=1; /bin/mv "$STAGE/app" "$APP" || fail 'Не удалось активировать backend.'
NEW_RUNTIME=1; /bin/mv "$STAGE/runtime" "$RUNTIME" || fail 'Не удалось активировать runtime.'
NEW_GUI_APP=1; /bin/mv "$STAGE/LocalTube.app" "$INSTALLED_APP" || fail 'Не удалось установить LocalTube.app.'
''', '''NEW_APP=1; /bin/mv "$STAGE/app" "$APP" || fail 'Не удалось активировать backend.'
if [ "$REPLACE_RUNTIME" -eq 1 ]; then
  NEW_RUNTIME=1; /bin/mv "$STAGE/runtime" "$RUNTIME" || fail 'Не удалось активировать runtime.'
else
  /bin/rm -rf "$STAGE/runtime" >/dev/null 2>&1 || true
fi
NEW_GUI_APP=1; /bin/mv "$STAGE/LocalTube.app" "$INSTALLED_APP" || fail 'Не удалось установить LocalTube.app.'
''', 1)

# Print the decision in the final report so support logs are self-explanatory.
s = s.replace('''say "Диагностика: $TOOLS_DIR/DIAGNOSE.command"
/usr/bin/open "http://127.0.0.1:$PORT/" >/dev/null 2>&1 || true
''', '''say "Диагностика: $TOOLS_DIR/DIAGNOSE.command"
if [ -n "$RUNTIME_DEFER_REASON" ]; then say "Runtime: $RUNTIME_DEFER_REASON"; fi
/usr/bin/open "http://127.0.0.1:$PORT/" >/dev/null 2>&1 || true
''', 1)
p.write_text(s, encoding='utf-8')

# Regression guard: installer must not regress back to the unconditional pgrep failure.
Path('scripts/check_installer_runtime_deferral.py').write_text(r'''#!/usr/bin/env python3
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
''', encoding='utf-8')

# Wire regression into the existing full test suite.
t = Path('scripts/test.sh').read_text(encoding='utf-8')
needle = "echo '[downloads] progress/temp-file/Windows installer regression'\npython3 scripts/check_progress_pipeline.py\n"
if needle not in t:
    raise SystemExit('scripts/test.sh anchor not found')
t = t.replace(needle, needle + "echo '[installer] active-runtime ownership/deferral regression'\npython3 scripts/check_installer_runtime_deferral.py\n", 1)
Path('scripts/test.sh').write_text(t, encoding='utf-8')

# Changelog entry.
c = Path('CHANGELOG.md')
text = c.read_text(encoding='utf-8')
entry = '''## 1.4.5\n\n- macOS installer distinguishes managed LocalTube jobs from orphan/manual `yt-dlp`/FFmpeg processes.\n- Active LocalTube downloads still block upgrades, but a compatible runtime used by an unrelated process is preserved instead of aborting the whole app/UI update.\n- Runtime ownership is checked before network bootstrap, avoiding pointless Deno/yt-dlp/FFmpeg re-downloads in the deferred-runtime path.\n- Runtime replacement is re-checked immediately before the transaction to close staging races.\n- Production package validation now includes the LocalTube branding assets.\n- Includes the new LocalTube favicon/header identity merged after 1.4.4.\n\n'''
if '## 1.4.5' not in text:
    # keep title/front matter intact if present
    pos = text.find('## ')
    text = text[:pos] + entry + text[pos:] if pos >= 0 else entry + text
    c.write_text(text, encoding='utf-8')
