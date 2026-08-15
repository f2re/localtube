#!/bin/bash
# LocalTube 1.4.2 macOS installer.
# Runs with a deterministic environment and does not source zsh/bash profiles.
# Compatible with Apple's /bin/bash 3.2.
set -u
umask 077

MODE="${1:---terminal}"

# Fast path used by CI/support to prove that the fallback launcher reaches a clean
# Bash process without reading user shell profiles. It deliberately runs before
# any macOS/install side effects.
if [ "$MODE" = '--self-test' ]; then
  case "${BASH_VERSION:-}" in '' ) printf 'ERROR: bash is not running\n' >&2; exit 2 ;; esac
  printf 'LocalTube installer self-test: OK (bash=%s, ENV=%s, BASH_ENV=%s, ZDOTDIR=%s)\n' \
    "$BASH_VERSION" "${ENV:-unset}" "${BASH_ENV:-unset}" "${ZDOTDIR:-unset}"
  exit 0
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" 2>/dev/null && pwd -P)" || exit 2
PACKAGE_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." 2>/dev/null && pwd -P)" || exit 2
PAYLOAD="$PACKAGE_ROOT/payload/app"
BASE="$HOME/Library/Application Support/LocalTube"
APP="$BASE/app"
RUNTIME="$BASE/runtime"
DATA="$BASE/data"
LOGS="$BASE/logs"
CACHE="$BASE/cache"
LABEL='com.localtube.service'
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM="$(/usr/bin/id -u)"
DOMAIN="gui/$UID_NUM"
STAGE="$BASE/.install-stage.$$"
BACKUP="$BASE/.rollback.$$"
USER_APPS="$HOME/Applications"
INSTALLED_APP="$USER_APPS/LocalTube.app"
TOOLS_DIR="$USER_APPS/LocalTube Tools"
DEFAULT_DOWNLOAD_DIR="$HOME/Movies/LocalTube"
LOCK_DIR="$BASE/.maintenance.lock"
LOCK_OWNED=0

TX_ACTIVE=0
OLD_SERVICE_LOADED=0
BACKED_APP=0
BACKED_RUNTIME=0
BACKED_PLIST=0
BACKED_GUI_APP=0
BACKED_TOOLS=0
BACKED_DATA=0
NEW_APP=0
NEW_RUNTIME=0
NEW_GUI_APP=0
NEW_TOOLS=0
NEW_PLIST=0

say() { printf '%s\n' "$*"; }
warn() { printf 'ПРЕДУПРЕЖДЕНИЕ: %s\n' "$*" >&2; }

gui_notify() {
  [ "$MODE" = '--gui' ] || return 0
  _gui_msg="$*"
  /usr/bin/osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "LocalTube"' -e 'end run' "$_gui_msg" >/dev/null 2>&1 || true
}

xml_escape() {
  printf '%s' "$1" | /usr/bin/sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"
}

is_macos() { [ "$(/usr/bin/uname -s 2>/dev/null)" = 'Darwin' ]; }
macos_version() { /usr/bin/sw_vers -productVersion 2>/dev/null || printf 'unknown'; }
service_loaded() { /bin/launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; }

bootout() {
  /bin/launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || \
    /bin/launchctl bootout "$DOMAIN" "$PLIST" >/dev/null 2>&1 || true
}

wait_service_unloaded() {
  _i=0; _limit="${1:-15}"
  while [ "$_i" -lt "$_limit" ]; do
    service_loaded || return 0
    /bin/sleep 1
    _i=$((_i + 1))
  done
  return 1
}

valid_port() {
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  [ "$1" -ge 1024 ] 2>/dev/null && [ "$1" -le 65535 ] 2>/dev/null
}

port_in_use() {
  _p="$1"
  if [ -x /usr/sbin/lsof ]; then
    /usr/sbin/lsof -nP -iTCP:"$_p" -sTCP:LISTEN 2>/dev/null | /usr/bin/grep -q LISTEN
    return $?
  fi
  if [ -x /usr/bin/nc ]; then
    /usr/bin/nc -z 127.0.0.1 "$_p" >/dev/null 2>&1
    return $?
  fi
  return 1
}

read_existing_port() {
  _p=''
  if [ -f "$DATA/port" ]; then _p="$(/usr/bin/tr -cd '0-9' < "$DATA/port" 2>/dev/null)"; fi
  if valid_port "$_p"; then printf '%s\n' "$_p"; else printf '%s\n' '8765'; fi
}

choose_port() {
  _preferred="$1"
  if valid_port "$_preferred" && ! port_in_use "$_preferred"; then printf '%s\n' "$_preferred"; return 0; fi
  _p=8765
  while [ "$_p" -le 8785 ]; do
    if ! port_in_use "$_p"; then printf '%s\n' "$_p"; return 0; fi
    _p=$((_p + 1))
  done
  return 1
}

write_plist() {
  _base="$(xml_escape "$BASE")"
  _home="$(xml_escape "$HOME")"
  _user="$(xml_escape "${USER:-$(/usr/bin/id -un)}")"
  _runner="$(xml_escape "$APP/scripts/run_server.sh")"
  _stdout="$(xml_escape "$LOGS/stdout.log")"
  _stderr="$(xml_escape "$LOGS/stderr.log")"
  _darwin_tmp="$(/usr/bin/getconf DARWIN_USER_TEMP_DIR 2>/dev/null || printf '/tmp')"
  case "$_darwin_tmp" in /*) ;; *) _darwin_tmp='/tmp' ;; esac
  _darwin_tmp="$(xml_escape "$_darwin_tmp")"
  _tmp="$PLIST.tmp.$$"
  /bin/rm -f "$_tmp"
  /bin/cat > "$_tmp" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/env</string>
    <string>-i</string>
    <string>HOME=$_home</string>
    <string>USER=$_user</string>
    <string>LOGNAME=$_user</string>
    <string>PATH=/usr/bin:/bin:/usr/sbin:/sbin</string>
    <string>LANG=en_US.UTF-8</string>
    <string>TMPDIR=$_darwin_tmp</string>
    <string>LOCALTUBE_BASE=$_base</string>
    <string>/bin/bash</string>
    <string>--noprofile</string>
    <string>--norc</string>
    <string>$_runner</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>ThrottleInterval</key><integer>5</integer>
  <key>StandardOutPath</key><string>$_stdout</string>
  <key>StandardErrorPath</key><string>$_stderr</string>
</dict>
</plist>
PLIST
  if ! /usr/bin/plutil -lint "$_tmp" >/dev/null 2>&1; then /bin/rm -f "$_tmp"; return 1; fi
  /bin/chmod 600 "$_tmp" >/dev/null 2>&1 || true
  /bin/mv -f "$_tmp" "$PLIST"
}

LAST_HEALTH_JSON=''
health() {
  _port="$(/bin/cat "$DATA/port" 2>/dev/null | /usr/bin/tr -cd '0-9')"
  _token="$(/bin/cat "$DATA/api_token" 2>/dev/null | /usr/bin/tr -d '\r\n')"
  valid_port "$_port" || return 1
  [ -n "$_token" ] || return 1
  _health_json="$(/usr/bin/curl --fail --silent --show-error --max-time 12 \
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
  if [ -n "$LAST_HEALTH_JSON" ]; then printf '%s\n' "$LAST_HEALTH_JSON"; else say '(health endpoint не вернул JSON)'; fi
  say '--- launchd state ---'
  /bin/launchctl print "$DOMAIN/$LABEL" 2>&1 | /usr/bin/tail -n 80 || true
  say '--- direct runtime checks ---'
  if [ -x "$RUNTIME/deno" ]; then "$RUNTIME/deno" --version 2>&1 | /usr/bin/head -n 3 || true; else say 'deno: missing'; fi
  if [ -x "$RUNTIME/yt-dlp" ]; then "$RUNTIME/yt-dlp" --version 2>&1 | /usr/bin/head -n 3 || true; else say 'yt-dlp: missing'; fi
  if [ -x "$RUNTIME/ffmpeg" ]; then "$RUNTIME/ffmpeg" -version 2>&1 | /usr/bin/head -n 3 || true; else say 'ffmpeg: missing'; fi
  if [ -x "$RUNTIME/ffprobe" ]; then "$RUNTIME/ffprobe" -version 2>&1 | /usr/bin/head -n 3 || true; else say 'ffprobe: missing'; fi
}

active_downloads() {
  _port="$(/bin/cat "$DATA/port" 2>/dev/null | /usr/bin/tr -cd '0-9')"
  _token="$(/bin/cat "$DATA/api_token" 2>/dev/null | /usr/bin/tr -d '\r\n')"
  valid_port "$_port" || return 1
  [ -n "$_token" ] || return 1
  _jobs="$(/usr/bin/curl --fail --silent --max-time 4 -H "X-LocalTube-Token: $_token" "http://127.0.0.1:$_port/api/jobs" 2>/dev/null)" || return 1
  printf '%s' "$_jobs" | /usr/bin/grep -Eq '"state":"(queued|running)"'
}

active_runtime_processes() {
  [ -x /usr/bin/pgrep ] || return 1
  /usr/bin/pgrep -f "$RUNTIME/yt-dlp" >/dev/null 2>&1 && return 0
  /usr/bin/pgrep -f "$RUNTIME/ffmpeg" >/dev/null 2>&1 && return 0
  return 1
}

acquire_lock() {
  if /bin/mkdir "$LOCK_DIR" 2>/dev/null; then
    LOCK_OWNED=1; printf '%s\n' "$$" > "$LOCK_DIR/pid"; return 0
  fi
  _lock_pid="$(/bin/cat "$LOCK_DIR/pid" 2>/dev/null | /usr/bin/tr -cd '0-9')"
  if [ -n "$_lock_pid" ] && /bin/kill -0 "$_lock_pid" >/dev/null 2>&1; then return 1; fi
  /bin/rm -rf "$LOCK_DIR" >/dev/null 2>&1 || return 1
  /bin/mkdir "$LOCK_DIR" 2>/dev/null || return 1
  LOCK_OWNED=1; printf '%s\n' "$$" > "$LOCK_DIR/pid"; return 0
}

restore_old_service() {
  if [ "$OLD_SERVICE_LOADED" -eq 1 ] && [ -f "$PLIST" ]; then
    /bin/launchctl bootstrap "$DOMAIN" "$PLIST" >/dev/null 2>&1 || true
    /bin/launchctl enable "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
    /bin/launchctl kickstart -k "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
  fi
}

rollback() {
  [ "$TX_ACTIVE" -eq 1 ] || return 0
  warn 'Новая версия не прошла финальную проверку; восстанавливаю предыдущее состояние.'
  bootout
  wait_service_unloaded >/dev/null 2>&1 || true

  if [ "$NEW_APP" -eq 1 ]; then /bin/rm -rf "$APP"; fi
  if [ "$NEW_RUNTIME" -eq 1 ]; then /bin/rm -rf "$RUNTIME"; fi
  if [ "$NEW_GUI_APP" -eq 1 ]; then /bin/rm -rf "$INSTALLED_APP"; fi
  if [ "$NEW_TOOLS" -eq 1 ]; then /bin/rm -rf "$TOOLS_DIR"; fi
  if [ "$NEW_PLIST" -eq 1 ]; then /bin/rm -f "$PLIST"; fi

  if [ "$BACKED_APP" -eq 1 ] && [ -d "$BACKUP/app" ]; then /bin/mv "$BACKUP/app" "$APP" || warn 'Не удалось автоматически вернуть предыдущий app.'; fi
  if [ "$BACKED_RUNTIME" -eq 1 ] && [ -d "$BACKUP/runtime" ]; then /bin/mv "$BACKUP/runtime" "$RUNTIME" || warn 'Не удалось автоматически вернуть предыдущий runtime.'; fi
  if [ "$BACKED_GUI_APP" -eq 1 ] && [ -d "$BACKUP/LocalTube.app" ]; then /bin/mv "$BACKUP/LocalTube.app" "$INSTALLED_APP" || warn 'Не удалось автоматически вернуть LocalTube.app.'; fi
  if [ "$BACKED_TOOLS" -eq 1 ] && [ -d "$BACKUP/LocalTube Tools" ]; then /bin/mv "$BACKUP/LocalTube Tools" "$TOOLS_DIR" || warn 'Не удалось автоматически вернуть инструменты.'; fi
  if [ "$BACKED_PLIST" -eq 1 ] && [ -f "$BACKUP/service.plist" ]; then /bin/cp "$BACKUP/service.plist" "$PLIST" || warn 'Не удалось автоматически вернуть LaunchAgent plist.'; fi

  if [ "$BACKED_DATA" -eq 1 ] && [ -d "$BACKUP/data" ]; then
    /bin/rm -rf "$DATA"
    /usr/bin/ditto "$BACKUP/data" "$DATA" || warn 'Не удалось полностью вернуть предыдущие настройки/историю.'
    /bin/chmod 700 "$DATA" >/dev/null 2>&1 || true
  fi
  restore_old_service
  TX_ACTIVE=0
}

cleanup() {
  /bin/rm -rf "$STAGE" >/dev/null 2>&1 || true
  if [ "$TX_ACTIVE" -eq 0 ]; then /bin/rm -rf "$BACKUP" >/dev/null 2>&1 || true; fi
  if [ "$LOCK_OWNED" -eq 1 ]; then /bin/rm -rf "$LOCK_DIR" >/dev/null 2>&1 || true; LOCK_OWNED=0; fi
}

fail() {
  _msg="$*"
  if [ "$TX_ACTIVE" -eq 1 ]; then rollback; fi
  printf '\nОШИБКА: %s\n' "$_msg" >&2
  exit 1
}

on_signal() {
  warn 'Установка прервана сигналом.'
  if [ "$TX_ACTIVE" -eq 1 ]; then rollback; fi
  exit 130
}

trap cleanup EXIT
trap on_signal HUP INT TERM

say 'LocalTube 1.4.2 — production installer'
say '======================================'
is_macos || fail 'Этот пакет предназначен только для macOS.'

OS_VERSION="$(macos_version)"
ARCH="$(/usr/bin/uname -m)"
case "$ARCH" in arm64|x86_64) ;; *) fail "Неподдерживаемая архитектура: $ARCH" ;; esac
say "macOS: $OS_VERSION"
say "CPU:   $ARCH"
say "HOME:  $HOME"
say 'zsh/Oh-My-Zsh/.zshrc: не используются.'

MAJOR="$(printf '%s' "$OS_VERSION" | /usr/bin/awk -F. '{print $1}')"
case "$MAJOR" in
  ''|*[!0-9]*) warn 'Не удалось определить версию macOS; совместимость проверит native self-test.' ;;
  *) [ "$MAJOR" -ge 11 ] 2>/dev/null || fail 'Требуется macOS 11 Big Sur или новее.' ;;
esac

if [ -f "$PACKAGE_ROOT/MANIFEST.sha256" ]; then
  say '[0/8] Проверяю целостность файлов пакета…'
  (cd "$PACKAGE_ROOT" && /usr/bin/shasum -a 256 -c MANIFEST.sha256 >/dev/null 2>&1) || fail 'Контрольные суммы пакета не совпали. Перекачайте архив из GitHub Releases.'
fi

for F in \
  "$PAYLOAD/server.ts" \
  "$PAYLOAD/VERSION" \
  "$PAYLOAD/static/index.html" \
  "$PAYLOAD/static/app.js" \
  "$PAYLOAD/static/styles.css" \
  "$PAYLOAD/scripts/runtime_common.sh" \
  "$PAYLOAD/scripts/service_common.sh" \
  "$PAYLOAD/scripts/run_server.sh" \
  "$PAYLOAD/scripts/update_runtime.sh" \
  "$PACKAGE_ROOT/app-template/LocalTube.app/Contents/Info.plist" \
  "$PACKAGE_ROOT/app-template/LocalTube.app/Contents/MacOS/LocalTube"; do
  [ -f "$F" ] || fail "Повреждён архив: отсутствует $F"
done

/bin/mkdir -p "$BASE" "$DATA" "$LOGS" "$CACHE" "$HOME/Library/LaunchAgents" "$USER_APPS" || fail 'Не удалось создать пользовательские каталоги.'
/bin/chmod 700 "$BASE" "$DATA" "$LOGS" "$CACHE" >/dev/null 2>&1 || true
acquire_lock || fail 'Уже выполняется установка или полное обновление LocalTube. Дождитесь её завершения.'

FREE_KB="$(/bin/df -Pk "$BASE" 2>/dev/null | /usr/bin/awk 'END {print $4}')"
case "$FREE_KB" in ''|*[!0-9]*) ;; *)
  [ "$FREE_KB" -ge 512000 ] || fail 'Недостаточно свободного места. Для безопасной установки нужно не менее 500 МБ свободно.'
  if [ "$FREE_KB" -lt 1048576 ]; then warn 'Свободно менее 1 ГБ; установка возможна, но для больших загрузок потребуется больше места.'; fi
;; esac

if service_loaded; then OLD_SERVICE_LOADED=1; fi
PREFERRED_PORT="$(read_existing_port)"

say '[1/8] Проверяю пакет и подготавливаю staging…'
/bin/rm -rf "$STAGE" "$BACKUP"
/bin/mkdir -p "$STAGE/app" "$STAGE/runtime" "$STAGE/LocalTube Tools" || fail 'Не удалось создать staging-каталог.'
/usr/bin/ditto "$PAYLOAD" "$STAGE/app" || fail 'Не удалось подготовить backend.'
/usr/bin/ditto "$PACKAGE_ROOT/app-template/LocalTube.app" "$STAGE/LocalTube.app" || fail 'Не удалось подготовить LocalTube.app.'
for F in START.command STOP.command UPDATE.command DIAGNOSE.command UNINSTALL.command; do
  /bin/cp "$PACKAGE_ROOT/control/$F" "$STAGE/LocalTube Tools/$F" || fail "Не удалось подготовить $F"
  /bin/chmod 755 "$STAGE/LocalTube Tools/$F"
done
/bin/chmod 755 "$STAGE/app/scripts/"*.sh "$STAGE/LocalTube.app/Contents/MacOS/LocalTube" >/dev/null 2>&1 || true

for F in "$STAGE/app/scripts/"*.sh; do /bin/bash --noprofile --norc -n "$F" || fail "Ошибка синтаксиса shell: $F"; done
for F in "$STAGE/LocalTube Tools/"*.command; do /bin/sh -n "$F" || fail "Ошибка синтаксиса shell: $F"; done
/usr/bin/plutil -lint "$STAGE/LocalTube.app/Contents/Info.plist" >/dev/null 2>&1 || fail 'Info.plist LocalTube.app повреждён.'

say '[2/8] Скачиваю проверенное окружение: Deno, yt-dlp, FFmpeg/FFprobe…'
gui_notify 'Скачиваю и проверяю Deno, yt-dlp и FFmpeg…'
. "$STAGE/app/scripts/runtime_common.sh" || fail 'Не удалось загрузить модуль установки окружения.'
LOCALTUBE_BOOTSTRAP_CACHE="$CACHE/bootstrap" LOCALTUBE_EXISTING_RUNTIME="$RUNTIME" lt_install_runtime "$STAGE/runtime" || fail 'Не удалось получить рабочее окружение ни из сети, ни из проверенного кэша, ни из предыдущей установки. Старая версия LocalTube не была остановлена.'

say '[3/8] Выполняю backend self-test на скачанном окружении…'
HOME="$HOME" LOCALTUBE_BASE="$STAGE" LOCALTUBE_APP_DIR="$STAGE/app" LOCALTUBE_RUNTIME_DIR="$STAGE/runtime" \
  "$STAGE/runtime/deno" run --no-config -A "$STAGE/app/server.ts" --self-test >/dev/null 2>&1 || \
  fail 'Backend не прошёл self-test. Старая версия LocalTube не была остановлена.'

say '[4/8] Проверяю native launcher и локальную подпись…'
if ! /usr/bin/codesign --force --sign - --timestamp=none "$STAGE/LocalTube.app" >/dev/null 2>&1; then
  warn 'Не удалось выполнить ad-hoc подпись staged LocalTube.app; продолжаю с native executable self-test.'
fi
"$STAGE/LocalTube.app/Contents/MacOS/LocalTube" --self-test >/dev/null 2>&1 || fail 'Native LocalTube.app не запускается на этой архитектуре macOS.'

say '[5/8] Переключаю версию транзакционно…'
gui_notify 'Проверки пройдены. Устанавливаю LocalTube…'

# Safety gate is deliberately BEFORE TX_ACTIVE: discovering an active download must never
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

TX_ACTIVE=1
/bin/mkdir -p "$BACKUP" || fail 'Не удалось создать каталог отката.'
if [ -f "$PLIST" ]; then /bin/cp "$PLIST" "$BACKUP/service.plist" || fail 'Не удалось сохранить предыдущий LaunchAgent.'; BACKED_PLIST=1; fi

# Stop only now: all downloads and preflight checks above completed with the previous service untouched.
bootout
wait_service_unloaded 15 || fail 'Не удалось корректно остановить предыдущий LaunchAgent за 15 секунд.'

# History/settings can be changing while the service is alive, therefore backup them only
# after a graceful stop. This gives rollback a consistent snapshot.
/usr/bin/ditto "$DATA" "$BACKUP/data" || fail 'Не удалось сохранить настройки и историю для отката.'
BACKED_DATA=1
PORT="$(choose_port "$PREFERRED_PORT")" || fail 'Не найден свободный локальный порт 8765–8785.'

if [ -d "$APP" ]; then BACKED_APP=1; /bin/mv "$APP" "$BACKUP/app" || fail 'Не удалось подготовить откат backend.'; fi
if [ -d "$RUNTIME" ]; then BACKED_RUNTIME=1; /bin/mv "$RUNTIME" "$BACKUP/runtime" || fail 'Не удалось подготовить откат runtime.'; fi
if [ -d "$INSTALLED_APP" ]; then BACKED_GUI_APP=1; /bin/mv "$INSTALLED_APP" "$BACKUP/LocalTube.app" || fail 'Не удалось подготовить откат LocalTube.app.'; fi
if [ -d "$TOOLS_DIR" ]; then BACKED_TOOLS=1; /bin/mv "$TOOLS_DIR" "$BACKUP/LocalTube Tools" || fail 'Не удалось подготовить откат инструментов.'; fi

NEW_APP=1; /bin/mv "$STAGE/app" "$APP" || fail 'Не удалось активировать backend.'
NEW_RUNTIME=1; /bin/mv "$STAGE/runtime" "$RUNTIME" || fail 'Не удалось активировать runtime.'
NEW_GUI_APP=1; /bin/mv "$STAGE/LocalTube.app" "$INSTALLED_APP" || fail 'Не удалось установить LocalTube.app.'
NEW_TOOLS=1; /bin/mv "$STAGE/LocalTube Tools" "$TOOLS_DIR" || fail 'Не удалось установить инструменты.'
/bin/chmod 755 "$APP/scripts/"*.sh "$INSTALLED_APP/Contents/MacOS/LocalTube" "$TOOLS_DIR/"*.command >/dev/null 2>&1 || true
/usr/bin/xattr -dr com.apple.quarantine "$APP" "$RUNTIME" "$INSTALLED_APP" "$TOOLS_DIR" >/dev/null 2>&1 || true
/usr/bin/codesign --force --sign - --timestamp=none "$INSTALLED_APP" >/dev/null 2>&1 || warn 'Не удалось повторно подписать установленный LocalTube.app.'

printf '%s\n' "$PORT" > "$DATA/port" || fail 'Не удалось записать локальный порт.'
/bin/chmod 600 "$DATA/port" >/dev/null 2>&1 || true
NEW_PLIST=1
write_plist || fail 'LaunchAgent plist не прошёл plutil -lint.'

say "      активирован порт 127.0.0.1:$PORT"
say '[6/8] Запускаю LaunchAgent в чистом окружении…'
if ! /bin/launchctl bootstrap "$DOMAIN" "$PLIST" >/dev/null 2>&1; then
  bootout; /bin/sleep 1
  /bin/launchctl bootstrap "$DOMAIN" "$PLIST" >/dev/null 2>&1 || fail "launchd не принял $PLIST"
fi
/bin/launchctl enable "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
/bin/launchctl kickstart -k "$DOMAIN/$LABEL" >/dev/null 2>&1 || true

say '[7/8] Проверяю authenticated HTTP health-check и готовность runtime…'
gui_notify 'Запускаю локальный сервис и проверяю его состояние…'
if ! wait_health; then
  print_health_diagnostics
  if [ -f "$LOGS/stderr.log" ]; then say '--- последние строки stderr ---'; /usr/bin/tail -n 80 "$LOGS/stderr.log" >&2 || true; fi
  fail 'LocalTube не вышел в состояние runtime.ready=true за 75 секунд. Диагностика напечатана выше; предыдущая версия восстановлена.'
fi
TOKEN="$(/bin/cat "$DATA/api_token" 2>/dev/null | /usr/bin/tr -d '\r\n')"
HEALTH_JSON="$LAST_HEALTH_JSON"
say '      runtime: ready'

say '[8/8] Проверяю интеграцию yt-dlp + Deno с YouTube (без скачивания видео)…'
DIAG_JSON="$(/usr/bin/curl --fail --silent --max-time 75 -H 'Content-Type: application/json' -H "X-LocalTube-Token: $TOKEN" -X POST --data '{}' "http://127.0.0.1:$PORT/api/diagnostics" 2>/dev/null || true)"
if printf '%s' "$DIAG_JSON" | /usr/bin/grep -q '"ok":true'; then
  # The response contains two ok fields; require YouTube detail as well to avoid treating the envelope only as success.
  if printf '%s' "$DIAG_JSON" | /usr/bin/grep -q 'YouTube extraction OK'; then say '      YouTube extraction: OK'; else warn 'Сервис работает, но онлайн-проверка YouTube не подтвердилась. Причина сохранится в DIAGNOSE.command.'; fi
else
  warn 'Онлайн-проверка YouTube недоступна; локальный сервис и runtime при этом прошли обязательные проверки.'
fi

trap - HUP INT TERM
TX_ACTIVE=0
/bin/rm -rf "$BACKUP" "$STAGE" >/dev/null 2>&1 || true

say ''
say 'ГОТОВО.'
say "LocalTube: http://127.0.0.1:$PORT/"
say "Приложение: $INSTALLED_APP"
say "Папка по умолчанию: $DEFAULT_DOWNLOAD_DIR"
say "Диагностика: $TOOLS_DIR/DIAGNOSE.command"
/usr/bin/open "http://127.0.0.1:$PORT/" >/dev/null 2>&1 || true
exit 0
