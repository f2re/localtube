#!/bin/bash
set -euo pipefail
umask 077

if [ "${1:-}" = '--self-test' ]; then
  if [ "$(uname -s 2>/dev/null || true)" = Linux ]; then echo 'LocalTube Linux installer self-test: OK'; else echo 'Linux installer self-test: SKIP'; fi
  exit 0
fi

[ "$(uname -s)" = Linux ] || { echo 'ERROR: this installer is for Linux.' >&2; exit 2; }
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
if [ -d "$SCRIPT_DIR/payload/app" ]; then PACKAGE_ROOT="$SCRIPT_DIR"; else PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"; fi
PAYLOAD="$PACKAGE_ROOT/payload/app"
[ -f "$PAYLOAD/server.ts" ] || { echo "ERROR: payload not found: $PAYLOAD" >&2; exit 2; }

BASE="${XDG_DATA_HOME:-$HOME/.local/share}/localtube"
APP="$BASE/app"; RUNTIME="$BASE/runtime"; DATA="$BASE/data"; LOGS="$BASE/logs"; CACHE="$BASE/cache"
STAGE="$BASE/.install-stage.$$"; BACKUP="$BASE/.rollback.$$"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
SYSTEMD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

mkdir -p "$BASE" "$DATA" "$LOGS" "$CACHE" "$BIN_DIR" "$DESKTOP_DIR"
rm -rf "$STAGE" "$BACKUP"; mkdir -p "$STAGE/app"
cp -a "$PAYLOAD/." "$STAGE/app/"
. "$STAGE/app/scripts/runtime_common.sh"

echo 'LocalTube — Linux installer'
echo '[1/5] installing runtime'
LOCALTUBE_BOOTSTRAP_CACHE="$CACHE/bootstrap" LOCALTUBE_EXISTING_RUNTIME="$RUNTIME" lt_install_runtime "$STAGE/runtime"

echo '[2/5] validating backend'
HOME="$HOME" LOCALTUBE_BASE="$STAGE" LOCALTUBE_APP_DIR="$STAGE/app" LOCALTUBE_RUNTIME_DIR="$STAGE/runtime" \
  "$STAGE/runtime/deno" run --no-config -A "$STAGE/app/server.ts" --self-test >/dev/null

echo '[3/5] replacing application atomically'
mkdir -p "$BACKUP"
[ -d "$APP" ] && mv "$APP" "$BACKUP/app"
[ -d "$RUNTIME" ] && mv "$RUNTIME" "$BACKUP/runtime"
mv "$STAGE/app" "$APP"
mv "$STAGE/runtime" "$RUNTIME"
rm -rf "$STAGE"
[ -f "$DATA/port" ] || printf '8765\n' > "$DATA/port"
chmod 700 "$DATA" "$LOGS" "$CACHE" 2>/dev/null || true

echo '[4/5] installing launcher'
mkdir -p "$BASE/control"
cp "$PACKAGE_ROOT/control/linux/localtube" "$BASE/control/localtube"
chmod 755 "$BASE/control/localtube"
cat > "$BIN_DIR/localtube" <<EOF
#!/bin/sh
exec "$BASE/control/localtube" "\${1:-start}"
EOF
chmod 755 "$BIN_DIR/localtube"

cat > "$DESKTOP_DIR/localtube.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=LocalTube
Comment=Локальная загрузка видео и аудио
Exec=$BASE/control/localtube start
Icon=video-x-generic
Terminal=false
Categories=AudioVideo;Network;
EOF
chmod 644 "$DESKTOP_DIR/localtube.desktop"

echo '[5/5] configuring user service'
if command -v systemctl >/dev/null 2>&1; then
  mkdir -p "$SYSTEMD_DIR"
  cat > "$SYSTEMD_DIR/localtube.service" <<EOF
[Unit]
Description=LocalTube local media downloader
After=network-online.target

[Service]
Type=simple
Environment="LOCALTUBE_BASE=$BASE"
ExecStart=/bin/bash --noprofile --norc "$APP/scripts/run_server.sh"
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable --now localtube.service >/dev/null 2>&1 || true
fi

rm -rf "$BACKUP"
"$BASE/control/localtube" start
echo "LocalTube installed in $BASE"
