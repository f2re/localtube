#!/bin/sh
BASE="$HOME/Library/Application Support/LocalTube"
LABEL='com.localtube.service'; UID_NUM=$(/usr/bin/id -u); DOMAIN="gui/$UID_NUM"; PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
PORT=$(/bin/cat "$BASE/data/port" 2>/dev/null | /usr/bin/tr -cd '0-9'); [ -n "$PORT" ] || PORT=8765
/bin/launchctl kickstart -k "$DOMAIN/$LABEL" >/dev/null 2>&1 || { /bin/launchctl bootstrap "$DOMAIN" "$PLIST" >/dev/null 2>&1 || true; /bin/launchctl kickstart -k "$DOMAIN/$LABEL" >/dev/null 2>&1 || true; }
I=0
while [ "$I" -lt 15 ]; do
  TOKEN=$(/bin/cat "$BASE/data/api_token" 2>/dev/null | /usr/bin/tr -d '\r\n')
  if [ -n "$TOKEN" ] && /usr/bin/curl -fsS --max-time 2 -H "X-LocalTube-Token: $TOKEN" "http://127.0.0.1:$PORT/api/health" 2>/dev/null | /usr/bin/grep -q '"ok":true'; then
    /usr/bin/open "http://127.0.0.1:$PORT/"; printf 'LocalTube запущен: http://127.0.0.1:%s/\n' "$PORT"; exit 0
  fi
  /bin/sleep 1; I=$((I + 1))
done
printf '%s\n' 'LocalTube не ответил за 15 секунд. Запустите DIAGNOSE.command.' >&2
exit 1
