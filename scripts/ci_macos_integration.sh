#!/bin/bash
# Real macOS integration test: install the same runtime as production, start the
# restricted Deno service and download yt-dlp's tiny public test video.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK="$(/usr/bin/mktemp -d -t localtube-ci.XXXXXX)"
BASE="$WORK/LocalTube"
APP="$BASE/app"; RUNTIME="$BASE/runtime"; DATA="$BASE/data"; LOGS="$BASE/logs"; DOWNLOADS="$WORK/downloads"
PID=''
cleanup() {
  if [ -n "$PID" ]; then /bin/kill "$PID" >/dev/null 2>&1 || true; fi
  /bin/rm -rf "$WORK" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM
/bin/mkdir -p "$APP" "$DATA" "$LOGS" "$DOWNLOADS"
/usr/bin/ditto "$ROOT/app" "$APP"

. "$APP/scripts/runtime_common.sh"
echo '[macOS 1/7] zsh + native launcher isolation'
ZDOTDIR="$WORK/hostile-zdot"
/bin/mkdir -p "$ZDOTDIR"
printf 'echo BROKEN_ZSHRC_WAS_READ\n' > "$ZDOTDIR/.zshrc"
_zsh_out="$(ZDOTDIR="$ZDOTDIR" /bin/zsh -f -c '"'$ROOT'/INSTALL.command" --self-test')"
printf '%s\n' "$_zsh_out" | /usr/bin/grep -q 'installer self-test: OK'
if printf '%s\n' "$_zsh_out" | /usr/bin/grep -q 'BROKEN_ZSHRC_WAS_READ'; then
  echo 'fallback installer read .zshrc' >&2
  exit 10
fi

VERSION="$(/bin/cat "$ROOT/app/VERSION")"
PKG="$ROOT/dist/LocalTube-macOS-v$VERSION"
"$PKG/Install LocalTube.app/Contents/MacOS/InstallLocalTube" --self-test | /usr/bin/grep -q 'self-test: OK'
"$PKG/app-template/LocalTube.app/Contents/MacOS/LocalTube" --self-test | /usr/bin/grep -q 'native launcher: OK'

echo '[macOS 2/7] install verified runtime'
lt_install_runtime "$RUNTIME"

echo '[macOS 3/7] Deno check + backend self-test'
"$RUNTIME/deno" check --no-config "$APP/server.ts"
HOME="$HOME" LOCALTUBE_BASE="$BASE" LOCALTUBE_APP_DIR="$APP" LOCALTUBE_RUNTIME_DIR="$RUNTIME" \
  "$RUNTIME/deno" run --no-config -A "$APP/server.ts" --self-test

echo '[macOS 4/7] start production-permission server'
PORT=18765
printf '%s\n' "$PORT" > "$DATA/port"
LOCALTUBE_BASE="$BASE" /bin/bash --noprofile --norc "$APP/scripts/run_server.sh" >"$LOGS/ci.stdout" 2>"$LOGS/ci.stderr" & PID=$!
TOKEN=''
I=0
while [ "$I" -lt 40 ]; do
  [ -f "$DATA/api_token" ] && TOKEN="$(/usr/bin/tr -d '\r\n' < "$DATA/api_token")"
  if [ -n "$TOKEN" ] && /usr/bin/curl -fsS --max-time 3 -H "X-LocalTube-Token: $TOKEN" "http://127.0.0.1:$PORT/api/health" | /usr/bin/grep -q '"ready":true'; then break; fi
  /bin/sleep 1
  I=$((I + 1))
done
[ -n "$TOKEN" ] || { /bin/cat "$LOGS/ci.stderr"; exit 20; }
/usr/bin/curl -fsS --max-time 3 -H "X-LocalTube-Token: $TOKEN" "http://127.0.0.1:$PORT/api/health" | /usr/bin/grep -q '"ready":true'

echo '[macOS 5/7] live YouTube extraction diagnostic'
DIAG="$(/usr/bin/curl -fsS --max-time 90 -H 'Content-Type: application/json' -H "X-LocalTube-Token: $TOKEN" -X POST --data '{}' "http://127.0.0.1:$PORT/api/diagnostics")"
printf '%s\n' "$DIAG" | /usr/bin/grep -q 'YouTube extraction OK' || { printf '%s\n' "$DIAG"; /bin/cat "$LOGS/ci.stderr"; exit 21; }

echo '[macOS 6/7] end-to-end 360p download through HTTP API'
PAYLOAD="$(python3 - "$DOWNLOADS" <<'PY'
import json,sys
print(json.dumps({"url":"https://www.youtube.com/watch?v=BaW_jenozKc","mode":"video","height":360,"download_dir":sys.argv[1],"video_container":"mp4","cookies_mode":"none","embed_metadata":False,"playlist":False}))
PY
)"
/usr/bin/curl -fsS --max-time 10 -H 'Content-Type: application/json' -H "X-LocalTube-Token: $TOKEN" -X POST --data "$PAYLOAD" "http://127.0.0.1:$PORT/api/jobs" >/dev/null
STATE=''
I=0
while [ "$I" -lt 180 ]; do
  JOBS="$(/usr/bin/curl -fsS --max-time 4 -H "X-LocalTube-Token: $TOKEN" "http://127.0.0.1:$PORT/api/jobs")"
  STATE="$(printf '%s' "$JOBS" | python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("jobs") or [{}])[0].get("state",""))')"
  case "$STATE" in completed) break ;; failed|cancelled|interrupted) printf '%s\n' "$JOBS"; /bin/cat "$LOGS/ci.stderr"; exit 22 ;; esac
  /bin/sleep 1
  I=$((I + 1))
done
[ "$STATE" = completed ] || { echo "download timeout: $STATE"; exit 23; }
/usr/bin/find "$DOWNLOADS" -type f ! -name '*.part' -size +1k -print -quit | /usr/bin/grep -q .
echo '[macOS 7/7] downloaded file verified'
echo 'macOS full integration: OK'
