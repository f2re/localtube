#!/bin/sh
BASE="$HOME/Library/Application Support/LocalTube"
LABEL='com.localtube.service'; UID_NUM=$(/usr/bin/id -u); DOMAIN="gui/$UID_NUM"; PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
PORT=$(/bin/cat "$BASE/data/port" 2>/dev/null | /usr/bin/tr -cd '0-9'); [ -n "$PORT" ] || PORT=8765
TOKEN=$(/bin/cat "$BASE/data/api_token" 2>/dev/null | /usr/bin/tr -d '\r\n')
REPORT="$HOME/Desktop/LocalTube-diagnostic-$(/bin/date '+%Y%m%d-%H%M%S').txt"

{
  printf '%s\n' 'LocalTube diagnostic report'
  printf 'Date: '; /bin/date
  printf 'macOS: '; /usr/bin/sw_vers -productVersion 2>/dev/null || true
  printf 'Architecture: '; /usr/bin/uname -m
  printf 'Login shell: %s (informational only; LocalTube does not source shell rc files)\n' "${SHELL:-unknown}"
  printf 'Base: %s\nPort: %s\n\n' "$BASE" "$PORT"

  printf '%s\n' '--- Files ---'
  for F in "$BASE/app/server.ts" "$BASE/runtime/deno" "$BASE/runtime/yt-dlp" "$BASE/runtime/ffmpeg" "$BASE/runtime/ffprobe" "$PLIST"; do
    if [ -e "$F" ]; then /bin/ls -ld "$F"; else printf 'MISSING: %s\n' "$F"; fi
  done
  printf '\n%s\n' '--- Versions ---'
  "$BASE/runtime/deno" --version 2>&1 | /usr/bin/head -n3 || true
  "$BASE/runtime/yt-dlp" --version 2>&1 | /usr/bin/head -n1 || true
  "$BASE/runtime/ffmpeg" -version 2>&1 | /usr/bin/head -n2 || true

  printf '\n%s\n' '--- plist ---'
  /usr/bin/plutil -lint "$PLIST" 2>&1 || true
  printf '\n%s\n' '--- launchd ---'
  /bin/launchctl print "$DOMAIN/$LABEL" 2>&1 | /usr/bin/head -n80 || true

  printf '\n%s\n' '--- authenticated local health ---'
  if [ -n "$TOKEN" ]; then
    /usr/bin/curl -sS --max-time 5 -H "X-LocalTube-Token: $TOKEN" "http://127.0.0.1:$PORT/api/health" 2>&1 || true
  else
    printf '%s\n' 'API token missing'
  fi

  printf '\n\n%s\n' '--- YouTube/EJS extraction check (no media is downloaded) ---'
  if [ -n "$TOKEN" ]; then
    /usr/bin/curl -sS --max-time 75 -H 'Content-Type: application/json' -H "X-LocalTube-Token: $TOKEN" \
      -X POST --data '{}' "http://127.0.0.1:$PORT/api/diagnostics" 2>&1 || true
  else
    printf '%s\n' 'Skipped: API token missing'
  fi

  printf '\n\n%s\n' '--- stderr tail ---'
  /usr/bin/tail -n 100 "$BASE/logs/stderr.log" 2>&1 || true
  printf '\n%s\n' '--- stdout tail ---'
  /usr/bin/tail -n 100 "$BASE/logs/stdout.log" 2>&1 || true

  printf '\n%s\n' '--- Port listeners ---'
  /usr/sbin/lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>&1 || true
} > "$REPORT" 2>&1

printf 'Диагностика сохранена: %s\n' "$REPORT"
/usr/bin/open -a TextEdit "$REPORT" >/dev/null 2>&1 || /usr/bin/open "$REPORT" >/dev/null 2>&1 || true
