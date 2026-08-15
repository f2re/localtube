#!/bin/bash
# Executed by launchd directly. It deliberately ignores the user's interactive shell setup.
# Apple /bin/bash 3.2 compatible.
set -u
umask 077

BASE="${LOCALTUBE_BASE:-$HOME/Library/Application Support/LocalTube}"
RUNTIME="$BASE/runtime"
APP="$BASE/app"
LOGS="$BASE/logs"
DATA="$BASE/data"
PORT='8765'

if [ -f "$DATA/port" ]; then
  READ_PORT="$(/usr/bin/tr -cd '0-9' < "$DATA/port" 2>/dev/null)"
  if [ -n "$READ_PORT" ] && [ "$READ_PORT" -ge 1024 ] 2>/dev/null && [ "$READ_PORT" -le 65535 ] 2>/dev/null; then PORT="$READ_PORT"; fi
fi

/bin/mkdir -p "$LOGS" "$DATA" "$BASE/cache/deno"
/bin/chmod 700 "$DATA" "$LOGS" "$BASE/cache" "$BASE/cache/deno" >/dev/null 2>&1 || true

[ -x "$RUNTIME/deno" ] || { printf 'LocalTube: Deno runtime missing: %s\n' "$RUNTIME/deno" >&2; exit 70; }
[ -x "$RUNTIME/yt-dlp" ] || { printf 'LocalTube: yt-dlp runtime missing: %s\n' "$RUNTIME/yt-dlp" >&2; exit 70; }
[ -x "$RUNTIME/ffmpeg" ] || { printf 'LocalTube: FFmpeg runtime missing: %s\n' "$RUNTIME/ffmpeg" >&2; exit 70; }
[ -x "$RUNTIME/ffprobe" ] || { printf 'LocalTube: FFprobe runtime missing: %s\n' "$RUNTIME/ffprobe" >&2; exit 70; }
[ -f "$APP/server.ts" ] || { printf 'LocalTube: server missing: %s\n' "$APP/server.ts" >&2; exit 71; }

# Deterministic environment. No ~/.zshrc, ~/.bashrc, Oh-My-Zsh, Homebrew or shell PATH is used.
export HOME
export LOCALTUBE_BASE="$BASE"
export LOCALTUBE_PORT="$PORT"
export DENO_DIR="$BASE/cache/deno"
export PATH="$RUNTIME:/usr/bin:/bin:/usr/sbin:/sbin"
export LANG="${LANG:-en_US.UTF-8}"
export TMPDIR="${TMPDIR:-/tmp}"
unset BASH_ENV ENV ZDOTDIR CDPATH PYTHONPATH PYTHONHOME NODE_OPTIONS DENO_CONFIG

# The backend needs arbitrary read/write access because the user can select any local download
# folder or cookies.txt. Other Deno capabilities remain restricted: no FFI, no subprocesses
# except the explicit tools below, and network listening only on loopback.
ALLOW_RUN="$RUNTIME/yt-dlp,$RUNTIME/ffmpeg,$RUNTIME/ffprobe,/usr/bin/osascript,/usr/bin/open,/usr/bin/pkill,/bin/df"
ALLOW_ENV='HOME,USER,LOGNAME,PATH,TMPDIR,LANG,LOCALTUBE_BASE,LOCALTUBE_PORT,LOCALTUBE_APP_DIR,LOCALTUBE_RUNTIME_DIR,DENO_DIR'

exec "$RUNTIME/deno" run --no-config --no-prompt \
  --allow-read --allow-write \
  "--allow-run=$ALLOW_RUN" \
  "--allow-env=$ALLOW_ENV" \
  "--allow-net=127.0.0.1:$PORT,localhost:$PORT" \
  "$APP/server.ts"
