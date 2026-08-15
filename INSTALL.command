#!/bin/sh
# macOS installer entry point.
# Works both from a packaged GitHub Release and directly from a git source checkout.
# It never sources ~/.zshrc, ~/.bashrc, Oh-My-Zsh, Homebrew shellenv, pyenv, etc.
set -u

SELF_DIR=$(CDPATH= cd -- "$(dirname "$0")" 2>/dev/null && pwd -P) || exit 2
MODE=${1:---terminal}
TMP_ROOT=''

cleanup() {
  if [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ]; then
    /bin/rm -rf "$TMP_ROOT" >/dev/null 2>&1 || true
  fi
}
trap cleanup 0 1 2 15

fail() {
  printf 'LocalTube: %s\n' "$*" >&2
  exit 2
}

run_clean_installer() {
  _root=$1
  /usr/bin/env -i \
    HOME="$HOME" \
    USER="${USER:-}" \
    LOGNAME="${LOGNAME:-${USER:-}}" \
    PATH='/usr/bin:/bin:/usr/sbin:/sbin' \
    /bin/bash --noprofile --norc "$_root/installer/install.sh" "$MODE"
}

# CI/support self-test must stay runnable even on a non-macOS runner. install.sh exits
# before any platform side effects in this mode and proves that no user rc files are read.
if [ "$MODE" = '--self-test' ] && [ -f "$SELF_DIR/installer/install.sh" ]; then
  trap - 0 1 2 15
  exec /usr/bin/env -i \
    HOME="$HOME" \
    USER="${USER:-}" \
    LOGNAME="${LOGNAME:-${USER:-}}" \
    PATH='/usr/bin:/bin:/usr/sbin:/sbin' \
    /bin/bash --noprofile --norc "$SELF_DIR/installer/install.sh" --self-test
fi

# Normal Release layout. Keep this fast path completely unchanged in semantics.
if [ -f "$SELF_DIR/payload/app/server.ts" ] && \
   [ -f "$SELF_DIR/app-template/LocalTube.app/Contents/Info.plist" ] && \
   [ -f "$SELF_DIR/app-template/LocalTube.app/Contents/MacOS/LocalTube" ]; then
  trap - 0 1 2 15
  exec /usr/bin/env -i \
    HOME="$HOME" \
    USER="${USER:-}" \
    LOGNAME="${LOGNAME:-${USER:-}}" \
    PATH='/usr/bin:/bin:/usr/sbin:/sbin' \
    /bin/bash --noprofile --norc "$SELF_DIR/installer/install.sh" "$MODE"
fi

# Source-checkout layout. A git clone contains app/, control/, installer/ and native/
# rather than the generated payload/ + app-template/ release tree. Build a temporary,
# self-contained package from the checkout using only tools shipped with macOS, then
# feed it to the exact same production installer used by Releases.
for _required in \
  "$SELF_DIR/app/server.ts" \
  "$SELF_DIR/app/VERSION" \
  "$SELF_DIR/app/static/index.html" \
  "$SELF_DIR/app/static/app.js" \
  "$SELF_DIR/app/static/styles.css" \
  "$SELF_DIR/app/scripts/runtime_common.sh" \
  "$SELF_DIR/app/scripts/service_common.sh" \
  "$SELF_DIR/app/scripts/run_server.sh" \
  "$SELF_DIR/app/scripts/update_runtime.sh" \
  "$SELF_DIR/installer/install.sh" \
  "$SELF_DIR/control/START.command" \
  "$SELF_DIR/control/STOP.command" \
  "$SELF_DIR/control/UPDATE.command" \
  "$SELF_DIR/control/DIAGNOSE.command" \
  "$SELF_DIR/control/UNINSTALL.command"; do
  [ -f "$_required" ] || fail "неполный source checkout: отсутствует $_required"
done

[ "$(/usr/bin/uname -s 2>/dev/null || true)" = 'Darwin' ] || fail 'INSTALL.command предназначен для macOS. Для Linux используйте Linux release/INSTALL.sh.'

TMP_ROOT=$(/usr/bin/mktemp -d -t localtube-source-install.XXXXXX 2>/dev/null) || fail 'не удалось создать временный каталог установки'
/bin/mkdir -p \
  "$TMP_ROOT/payload" \
  "$TMP_ROOT/control" \
  "$TMP_ROOT/installer" \
  "$TMP_ROOT/app-template/LocalTube.app/Contents/MacOS" || fail 'не удалось подготовить временный пакет'

/usr/bin/ditto "$SELF_DIR/app" "$TMP_ROOT/payload/app" || fail 'не удалось скопировать backend из source checkout'
/bin/cp "$SELF_DIR/installer/install.sh" "$TMP_ROOT/installer/install.sh" || fail 'не удалось подготовить installer'
for _name in START.command STOP.command UPDATE.command DIAGNOSE.command UNINSTALL.command; do
  /bin/cp "$SELF_DIR/control/$_name" "$TMP_ROOT/control/$_name" || fail "не удалось подготовить $_name"
  /bin/chmod 755 "$TMP_ROOT/control/$_name" >/dev/null 2>&1 || true
done
/bin/chmod 755 "$TMP_ROOT/installer/install.sh" "$TMP_ROOT/payload/app/scripts/"*.sh >/dev/null 2>&1 || true

# A Release contains a universal Go launcher. A source checkout deliberately does not
# commit generated binaries. For source installation synthesize a dependency-free app
# bundle whose executable is /bin/sh. LaunchServices executes it directly (no Terminal,
# no zsh), and the production installer still performs the same backend/runtime checks.
/bin/cat > "$TMP_ROOT/app-template/LocalTube.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>ru</string>
  <key>CFBundleDisplayName</key><string>LocalTube</string>
  <key>CFBundleExecutable</key><string>LocalTube</string>
  <key>CFBundleIdentifier</key><string>ru.localtube.app</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>LocalTube</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

/bin/cat > "$TMP_ROOT/app-template/LocalTube.app/Contents/MacOS/LocalTube" <<'LAUNCHER'
#!/bin/sh
set -u
if [ "${1:-}" = '--self-test' ]; then
  printf '%s\n' 'LocalTube source launcher: OK'
  exit 0
fi

HOME_DIR=${HOME:-}
[ -n "$HOME_DIR" ] || exit 2
BASE="$HOME_DIR/Library/Application Support/LocalTube"
DATA="$BASE/data"
PORT='8765'
if [ -f "$DATA/port" ]; then
  _p=$(/usr/bin/tr -cd '0-9' < "$DATA/port" 2>/dev/null)
  case "$_p" in ''|*[!0-9]*) ;; *) if [ "$_p" -ge 1024 ] 2>/dev/null && [ "$_p" -le 65535 ] 2>/dev/null; then PORT=$_p; fi ;; esac
fi

health() {
  [ -f "$DATA/api_token" ] || return 1
  _token=$(/usr/bin/tr -d '\r\n' < "$DATA/api_token" 2>/dev/null)
  [ -n "$_token" ] || return 1
  /usr/bin/curl -q --noproxy '*' --http1.1 --fail --silent --max-time 3 \
    -H "X-LocalTube-Token: $_token" \
    "http://127.0.0.1:$PORT/api/health" 2>/dev/null | /usr/bin/grep -q '"ready":true'
}

if ! health; then
  _uid=$(/usr/bin/id -u)
  _domain="gui/$_uid"
  _label='com.localtube.service'
  _plist="$HOME_DIR/Library/LaunchAgents/$_label.plist"
  /bin/launchctl kickstart -k "$_domain/$_label" >/dev/null 2>&1 || {
    [ -f "$_plist" ] && /bin/launchctl bootstrap "$_domain" "$_plist" >/dev/null 2>&1 || true
    /bin/launchctl enable "$_domain/$_label" >/dev/null 2>&1 || true
    /bin/launchctl kickstart -k "$_domain/$_label" >/dev/null 2>&1 || true
  }
  _i=0
  while [ "$_i" -lt 20 ]; do
    health && break
    /bin/sleep 1
    _i=$((_i + 1))
  done
fi

if health; then
  /usr/bin/open "http://127.0.0.1:$PORT/" >/dev/null 2>&1
  exit $?
fi

_diag="$HOME_DIR/Applications/LocalTube Tools/DIAGNOSE.command"
/usr/bin/osascript -e 'on run argv' \
  -e 'display dialog ("LocalTube не запустился. Запустите диагностику:" & return & item 1 of argv) with title "LocalTube" buttons {"OK"} default button "OK" with icon stop' \
  -e 'end run' "$_diag" >/dev/null 2>&1 || true
exit 1
LAUNCHER
/bin/chmod 755 "$TMP_ROOT/app-template/LocalTube.app/Contents/MacOS/LocalTube" || fail 'не удалось сделать source launcher исполняемым'

if [ "$MODE" = '--layout-self-test' ]; then
  /usr/bin/plutil -lint "$TMP_ROOT/app-template/LocalTube.app/Contents/Info.plist" >/dev/null 2>&1 || fail 'source Info.plist не прошёл plutil'
  /bin/sh -n "$TMP_ROOT/app-template/LocalTube.app/Contents/MacOS/LocalTube" || fail 'ошибка синтаксиса source launcher'
  /bin/bash --noprofile --norc -n "$TMP_ROOT/installer/install.sh" || fail 'ошибка синтаксиса installer/install.sh'
  "$TMP_ROOT/app-template/LocalTube.app/Contents/MacOS/LocalTube" --self-test >/dev/null 2>&1 || fail 'source launcher self-test failed'
  [ -f "$TMP_ROOT/payload/app/server.ts" ] || fail 'source payload synthesis failed'
  printf '%s\n' 'LocalTube source-checkout layout self-test: OK'
  exit 0
fi

printf '%s\n' 'LocalTube: обнаружен git/source checkout; формирую временный production-пакет без Go/Python/Homebrew.'
run_clean_installer "$TMP_ROOT"
_rc=$?
exit "$_rc"
