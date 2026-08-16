#!/bin/bash
# Real macOS integration test: install the same runtime as production, start the
# restricted Deno service and exercise yt-dlp's current upstream YouTube fixture.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK="$(/usr/bin/mktemp -d -t localtube-ci.XXXXXX)"
BASE="$WORK/LocalTube"
APP="$BASE/app"; RUNTIME="$BASE/runtime"; DATA="$BASE/data"; LOGS="$BASE/logs"; DOWNLOADS="$WORK/downloads"
PID=''
cleanup() {
  if [ -n "$PID" ]; then /bin/kill "$PID" >/dev/null 2>&1 || true; fi
  if [ "${CURLRC_HAD_ORIGINAL:-0}" -eq 1 ] && [ -f "${CURLRC_BACKUP:-}" ]; then
    /bin/cp "$CURLRC_BACKUP" "$HOME/.curlrc"
  else
    /bin/rm -f "$HOME/.curlrc"
  fi
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

echo '[macOS curl] hostile ~/.curlrc isolation test'
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

echo '[macOS 4/7] start production-permission server'
PORT=18765
printf '%s\n' "$PORT" > "$DATA/port"
LOCALTUBE_BASE="$BASE" /bin/bash --noprofile --norc "$APP/scripts/run_server.sh" >"$LOGS/ci.stdout" 2>"$LOGS/ci.stderr" & PID=$!
TOKEN=''
I=0
while [ "$I" -lt 40 ]; do
  [ -f "$DATA/api_token" ] && TOKEN="$(/usr/bin/tr -d '\r\n' < "$DATA/api_token")"
  if [ -n "$TOKEN" ] && /usr/bin/curl -q --noproxy '*' --http1.1 -fsS --max-time 3 -H "X-LocalTube-Token: $TOKEN" "http://127.0.0.1:$PORT/api/health" | /usr/bin/grep -q '"ready":true'; then break; fi
  /bin/sleep 1
  I=$((I + 1))
done
[ -n "$TOKEN" ] || { /bin/cat "$LOGS/ci.stderr"; exit 20; }
/usr/bin/curl -q --noproxy '*' --http1.1 -fsS --max-time 3 -H "X-LocalTube-Token: $TOKEN" "http://127.0.0.1:$PORT/api/health" | /usr/bin/grep -q '"ready":true'

echo '[macOS 5/7] live YouTube extraction diagnostic'
DIAG_JSON="$(/usr/bin/curl -q --noproxy '*' --http1.1 -fsS --max-time 45 -H 'Content-Type: application/json' -H "X-LocalTube-Token: $TOKEN" -X POST --data '{}' "http://127.0.0.1:$PORT/api/diagnostics")"
printf '%s\n' "$DIAG_JSON"
YT_RESULT="$(printf '%s' "$DIAG_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin)["diagnostics"]["youtube"]; print("ok" if d.get("ok") else "fail"); print(d.get("detail", ""))')"
YT_STATE="$(printf '%s\n' "$YT_RESULT" | /usr/bin/head -n 1)"
YT_DETAIL="$(printf '%s\n' "$YT_RESULT" | /usr/bin/tail -n +2)"
LIVE_YOUTUBE=0
if [ "$YT_STATE" = ok ]; then
  LIVE_YOUTUBE=1
elif printf '%s' "$YT_DETAIL" | /usr/bin/grep -Eqi "confirm you.re not a bot|too many requests|HTTP Error 429"; then
  echo "::warning::YouTube blocked the GitHub-hosted runner as an automated/datacenter client. Runtime/extractor startup succeeded; using deterministic local-media E2E for the HTTP queue path."
else
  printf '%s\n' "$YT_DETAIL"
  /bin/cat "$LOGS/ci.stderr"
  exit 21
fi

if [ "$LIVE_YOUTUBE" -eq 0 ]; then
  /bin/mv "$RUNTIME/yt-dlp" "$RUNTIME/yt-dlp.real"
  /bin/cat > "$RUNTIME/yt-dlp" <<'MOCK'
#!/bin/sh
set -eu
if [ "${1:-}" = "--version" ]; then printf '%s\n' 'LocalTube-CI-mock'; exit 0; fi
OUTDIR="$PWD"
TMPDIR="$PWD"
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--paths" ] && [ "$#" -ge 2 ]; then
    case "$2" in
      temp:*) TMPDIR=${2#temp:} ;;
      *) OUTDIR=$2 ;;
    esac
    shift 2
    continue
  fi
  shift
done
/bin/mkdir -p "$OUTDIR" "$TMPDIR"
FFMPEG="$(dirname "$0")/ffmpeg"
TMP="$TMPDIR/LocalTube CI synthetic [localtube-ci].mp4"
OUT="$OUTDIR/LocalTube CI synthetic [localtube-ci].mp4"
"$FFMPEG" -hide_banner -loglevel error -y -f lavfi -i 'color=c=black:s=320x180:d=1' -f lavfi -i 'anullsrc=r=44100:cl=stereo' -t 1 -c:v mpeg4 -c:a aac "$TMP"
SIZE=$(/usr/bin/stat -f %z "$TMP")
printf '__LOCALTUBE_PROGRESS__:downloading\tlocal\t%s\t%s\tNA\t1048576\t0\tNA\tNA\t%s\n' "$SIZE" "$SIZE" "$TMP"
printf '__LOCALTUBE_POSTPROCESS__:started\n'
/bin/mv "$TMP" "$OUT"
printf '__LOCALTUBE_FINAL__:%s\n' "$OUT"
MOCK
  /bin/chmod 755 "$RUNTIME/yt-dlp"
fi

echo '[macOS 6/7] end-to-end queue/download path through HTTP API'
PAYLOAD="$(python3 - "$DOWNLOADS" <<'PY'
import json,sys
print(json.dumps({"url":"https://www.youtube.com/watch?v=YE7VzlLtp-4&t=1s&end=9","mode":"video","height":360,"download_dir":sys.argv[1],"video_container":"mp4","cookies_mode":"none","embed_metadata":False,"playlist":False}))
PY
)"
/usr/bin/curl -q --noproxy '*' --http1.1 -fsS --max-time 10 -H 'Content-Type: application/json' -H "X-LocalTube-Token: $TOKEN" -X POST --data "$PAYLOAD" "http://127.0.0.1:$PORT/api/jobs" >/dev/null
STATE=''
I=0
while [ "$I" -lt 180 ]; do
  JOBS="$(/usr/bin/curl -q --noproxy '*' --http1.1 -fsS --max-time 4 -H "X-LocalTube-Token: $TOKEN" "http://127.0.0.1:$PORT/api/jobs")"
  STATE="$(printf '%s' "$JOBS" | python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("jobs") or [{}])[0].get("state",""))')"
  case "$STATE" in completed) break ;; failed|cancelled|interrupted) printf '%s\n' "$JOBS"; /bin/cat "$LOGS/ci.stderr"; exit 22 ;; esac
  /bin/sleep 1
  I=$((I + 1))
done
[ "$STATE" = completed ] || { echo "download timeout: $STATE"; exit 23; }
OUTPUT="$(/usr/bin/find "$DOWNLOADS" -maxdepth 1 -type f -size +1k -print -quit)"
[ -n "$OUTPUT" ] || { echo 'No completed output file'; exit 24; }
if [ -d "$DOWNLOADS/.localtube-tmp" ] && /usr/bin/find "$DOWNLOADS/.localtube-tmp" -mindepth 1 -print -quit | /usr/bin/grep -q .; then
  echo 'Per-job temporary files were not cleaned up' >&2
  /usr/bin/find "$DOWNLOADS/.localtube-tmp" -print >&2
  exit 25
fi
FINAL_SIZE="$(printf '%s' "$JOBS" | python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("jobs") or [{}])[0].get("final_size_bytes",0))')"
[ "$FINAL_SIZE" -gt 1024 ] || { printf '%s\n' "$JOBS"; echo 'Final size was not recorded' >&2; exit 26; }
"$RUNTIME/ffprobe" -v error -show_entries format=duration -of default=nw=1:nk=1 "$OUTPUT" >/dev/null
if [ "$LIVE_YOUTUBE" -eq 1 ]; then
  echo '[macOS 7/7] real YouTube download verified'
else
  echo '[macOS 7/7] deterministic queue + temp cleanup + FFmpeg output verified; live YouTube probe was CI-IP blocked'
fi
echo 'macOS full integration: OK'
