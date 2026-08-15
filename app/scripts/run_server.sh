#!/bin/bash
# LocalTube server launcher for macOS/Linux. No interactive shell profiles are sourced.
set -u
umask 077

OS="$(uname -s 2>/dev/null || printf unknown)"
case "$OS" in
  Darwin) DEFAULT_BASE="$HOME/Library/Application Support/LocalTube" ;;
  Linux) DEFAULT_BASE="${XDG_DATA_HOME:-$HOME/.local/share}/localtube" ;;
  *) printf 'LocalTube: unsupported Unix platform: %s\n' "$OS" >&2; exit 69 ;;
esac

BASE="${LOCALTUBE_BASE:-$DEFAULT_BASE}"
RUNTIME="$BASE/runtime"
APP="$BASE/app"
LOGS="$BASE/logs"
DATA="$BASE/data"
PORT='8765'

if [ -f "$DATA/port" ]; then
  READ_PORT="$(tr -cd '0-9' < "$DATA/port" 2>/dev/null)"
  if [ -n "$READ_PORT" ] && [ "$READ_PORT" -ge 1024 ] 2>/dev/null && [ "$READ_PORT" -le 65535 ] 2>/dev/null; then PORT="$READ_PORT"; fi
fi

mkdir -p "$LOGS" "$DATA" "$BASE/cache/deno"
chmod 700 "$DATA" "$LOGS" "$BASE/cache" "$BASE/cache/deno" >/dev/null 2>&1 || true
printf '%s\n' "$$" > "$DATA/server.pid"

for tool in deno yt-dlp ffmpeg ffprobe; do
  [ -x "$RUNTIME/$tool" ] || { printf 'LocalTube: runtime missing: %s\n' "$RUNTIME/$tool" >&2; exit 70; }
done
[ -f "$APP/server.ts" ] || { printf 'LocalTube: server missing: %s\n' "$APP/server.ts" >&2; exit 71; }

export HOME
export LOCALTUBE_BASE="$BASE"
export LOCALTUBE_PORT="$PORT"
export DENO_DIR="$BASE/cache/deno"
if [ "$OS" = Darwin ]; then
  export PATH="$RUNTIME:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
else
  export PATH="$RUNTIME:/usr/local/bin:/usr/bin:/bin"
fi
export LANG="${LANG:-en_US.UTF-8}"
export TMPDIR="${TMPDIR:-/tmp}"
unset BASH_ENV ENV ZDOTDIR CDPATH PYTHONPATH PYTHONHOME NODE_OPTIONS DENO_CONFIG

ALLOW_RUN="$RUNTIME/yt-dlp,$RUNTIME/ffmpeg,$RUNTIME/ffprobe"
if [ "$OS" = Darwin ]; then
  ALLOW_RUN="$ALLOW_RUN,/usr/bin/osascript,/usr/bin/open,/usr/bin/pkill,/bin/df,/usr/bin/df"
else
  for cmd in /usr/bin/pkill /bin/pkill /bin/df /usr/bin/df /usr/bin/xdg-open /usr/bin/zenity /usr/bin/kdialog; do
    [ -x "$cmd" ] && ALLOW_RUN="$ALLOW_RUN,$cmd"
  done
fi
ALLOW_ENV='HOME,USER,LOGNAME,PATH,TMPDIR,LANG,LOCALTUBE_BASE,LOCALTUBE_PORT,LOCALTUBE_APP_DIR,LOCALTUBE_RUNTIME_DIR,DENO_DIR,XDG_DATA_HOME,XDG_CONFIG_HOME,XDG_CACHE_HOME,DISPLAY,WAYLAND_DISPLAY'

exec "$RUNTIME/deno" run --no-config --no-prompt \
  --allow-read --allow-write \
  "--allow-run=$ALLOW_RUN" \
  "--allow-env=$ALLOW_ENV" \
  "--allow-net=127.0.0.1:$PORT,localhost:$PORT" \
  "$APP/server.ts"
