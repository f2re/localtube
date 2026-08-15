#!/bin/bash
# Transactional update of LocalTube private runtime with rollback.
# Compatible with Apple's /bin/bash 3.2 and independent from zsh/user rc files.
set -u
umask 077

BASE="${LOCALTUBE_BASE:-$HOME/Library/Application Support/LocalTube}"
APP="$BASE/app"
RUNTIME="$BASE/runtime"
NEW="$BASE/runtime.new.$$"
OLD="$BASE/runtime.rollback.$$"
LOCK_DIR="$BASE/.maintenance.lock"
LOCK_OWNED=0

. "$APP/scripts/runtime_common.sh" || exit 2
. "$APP/scripts/service_common.sh" || exit 2

TX_ACTIVE=0
OLD_SERVICE_LOADED=0
OLD_RUNTIME_MOVED=0
NEW_RUNTIME_ACTIVE=0
SUCCESS=0

say() { printf '%s\n' "$*"; }
warn() { printf 'ПРЕДУПРЕЖДЕНИЕ: %s\n' "$*" >&2; }

acquire_lock() {
  if /bin/mkdir "$LOCK_DIR" 2>/dev/null; then LOCK_OWNED=1; printf '%s\n' "$$" > "$LOCK_DIR/pid"; return 0; fi
  _lock_pid="$(/bin/cat "$LOCK_DIR/pid" 2>/dev/null | /usr/bin/tr -cd '0-9')"
  if [ -n "$_lock_pid" ] && /bin/kill -0 "$_lock_pid" >/dev/null 2>&1; then return 1; fi
  /bin/rm -rf "$LOCK_DIR" >/dev/null 2>&1 || return 1
  /bin/mkdir "$LOCK_DIR" 2>/dev/null || return 1
  LOCK_OWNED=1; printf '%s\n' "$$" > "$LOCK_DIR/pid"; return 0
}

cleanup() {
  /bin/rm -rf "$NEW" >/dev/null 2>&1 || true
  if [ "$SUCCESS" -eq 1 ]; then /bin/rm -rf "$OLD" >/dev/null 2>&1 || true; fi
  if [ "$LOCK_OWNED" -eq 1 ]; then /bin/rm -rf "$LOCK_DIR" >/dev/null 2>&1 || true; LOCK_OWNED=0; fi
}

restore_service_state() {
  if [ "$OLD_SERVICE_LOADED" -eq 1 ]; then
    lt_bootstrap >/dev/null 2>&1 || true
    lt_wait_health 25 >/dev/null 2>&1 || true
  else
    lt_bootout >/dev/null 2>&1 || true
  fi
}

rollback_update() {
  [ "$TX_ACTIVE" -eq 1 ] || return 0
  warn 'Обновление прервано или не прошло проверку; восстанавливаю предыдущий runtime.'
  lt_bootout >/dev/null 2>&1 || true
  if [ "$NEW_RUNTIME_ACTIVE" -eq 1 ]; then /bin/rm -rf "$RUNTIME" >/dev/null 2>&1 || true; fi
  if [ "$OLD_RUNTIME_MOVED" -eq 1 ] && [ -d "$OLD" ]; then
    /bin/mv "$OLD" "$RUNTIME" || warn 'Не удалось автоматически вернуть предыдущий runtime.'
  fi
  restore_service_state
  TX_ACTIVE=0
}

on_signal() {
  warn 'Обновление прервано сигналом.'
  rollback_update
  exit 130
}

trap cleanup EXIT
trap on_signal HUP INT TERM

say 'LocalTube — безопасное обновление окружения'
say '-------------------------------------------'
[ -d "$APP" ] || { say 'LocalTube не установлен.' >&2; exit 2; }
[ -f "$APP/server.ts" ] || { say 'Backend LocalTube повреждён.' >&2; exit 2; }
acquire_lock || { say 'Уже выполняется установка или полное обновление LocalTube.' >&2; exit 3; }

# All network work happens before touching the active service/runtime.
lt_install_runtime "$NEW" || { say 'Новое окружение не установлено: текущая версия оставлена без изменений.' >&2; exit 10; }

HOME="$HOME" LOCALTUBE_BASE="$BASE" LOCALTUBE_APP_DIR="$APP" LOCALTUBE_RUNTIME_DIR="$NEW" \
  "$NEW/deno" run --no-config -A "$APP/server.ts" --self-test >/dev/null 2>&1 || {
    say 'Новое окружение не прошло backend self-test; текущая версия оставлена.' >&2
    exit 11
  }

if lt_loaded; then OLD_SERVICE_LOADED=1; fi
if lt_health && lt_has_active_jobs; then
  say 'Есть активные загрузки. Обновление отменено, чтобы не прерывать их.' >&2
  exit 12
fi
if lt_has_active_runtime_processes; then
  say 'Обнаружен активный процесс yt-dlp/FFmpeg текущего runtime. Обновление не будет его прерывать.' >&2
  exit 12
fi
TX_ACTIVE=1

if [ "$OLD_SERVICE_LOADED" -eq 1 ]; then
  lt_bootout
  if ! lt_wait_unloaded 15; then
    rollback_update
    say 'Не удалось корректно остановить LaunchAgent за 15 секунд; обновление отменено.' >&2
    exit 13
  fi
fi

if [ -d "$RUNTIME" ]; then
  OLD_RUNTIME_MOVED=1
  /bin/mv "$RUNTIME" "$OLD" || { rollback_update; say 'Не удалось подготовить каталог отката.' >&2; exit 12; }
fi
NEW_RUNTIME_ACTIVE=1
if ! /bin/mv "$NEW" "$RUNTIME"; then
  rollback_update
  say 'Не удалось активировать новое окружение; выполнен откат.' >&2
  exit 13
fi

# Verify the activated files once more at their final paths.
HOME="$HOME" LOCALTUBE_BASE="$BASE" LOCALTUBE_APP_DIR="$APP" LOCALTUBE_RUNTIME_DIR="$RUNTIME" \
  "$RUNTIME/deno" run --no-config -A "$APP/server.ts" --self-test >/dev/null 2>&1 || {
    rollback_update
    say 'Активированное окружение не прошло финальный self-test; выполнен откат.' >&2
    exit 14
  }

if [ "$OLD_SERVICE_LOADED" -eq 1 ]; then
  if ! lt_bootstrap || ! lt_wait_health 35; then
    rollback_update
    say 'Новая версия не запустилась; выполнен автоматический откат.' >&2
    exit 15
  fi
else
  # Preserve an intentionally stopped service. The native self-test above is sufficient here.
  lt_bootout >/dev/null 2>&1 || true
fi

trap - HUP INT TERM
TX_ACTIVE=0
SUCCESS=1
/bin/rm -rf "$OLD" >/dev/null 2>&1 || true
say 'Окружение обновлено и прошло обязательные проверки.'
if [ "$OLD_SERVICE_LOADED" -eq 1 ]; then say 'Сервис снова отвечает корректно.'; else say 'Сервис был остановлен до обновления и оставлен остановленным.'; fi
exit 0
