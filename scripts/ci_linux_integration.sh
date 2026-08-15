#!/bin/bash
set -euo pipefail
[ "$(uname -s)" = Linux ] || { echo 'Linux integration: SKIP'; exit 0; }
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
WORK="$(mktemp -d)"
BASE="$WORK/localtube"
mkdir -p "$BASE/app" "$BASE/data" "$BASE/logs"
cp -a "$ROOT/app/." "$BASE/app/"
cleanup() { [ -n "${PID:-}" ] && kill "$PID" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT
. "$BASE/app/scripts/runtime_common.sh"

echo '[linux 1/4] install verified runtime'
lt_install_runtime "$BASE/runtime"

echo '[linux 2/4] backend self-test'
HOME="$HOME" XDG_DATA_HOME="$WORK/xdg" LOCALTUBE_BASE="$BASE" LOCALTUBE_APP_DIR="$BASE/app" LOCALTUBE_RUNTIME_DIR="$BASE/runtime" \
  "$BASE/runtime/deno" run --no-config -A "$BASE/app/server.ts" --self-test

echo '[linux 3/4] restricted server start'
printf '18766\n' > "$BASE/data/port"
LOCALTUBE_BASE="$BASE" /bin/bash --noprofile --norc "$BASE/app/scripts/run_server.sh" >"$BASE/logs/out" 2>"$BASE/logs/err" &
PID=$!
TOKEN=''
for _ in $(seq 1 40); do
  [ -f "$BASE/data/api_token" ] && TOKEN="$(tr -d '\r\n' < "$BASE/data/api_token")" || TOKEN=''
  if [ -n "$TOKEN" ] && curl -fsS --max-time 3 -H "X-LocalTube-Token: $TOKEN" http://127.0.0.1:18766/api/health | grep -q '"ready":true'; then break; fi
  sleep 1
done
[ -n "$TOKEN" ] || { cat "$BASE/logs/err"; exit 1; }
curl -fsS -H "X-LocalTube-Token: $TOKEN" http://127.0.0.1:18766/api/health | grep -q '"platform":"linux"'
echo '[linux 4/4] health OK'
kill "$PID" >/dev/null 2>&1 || true
wait "$PID" 2>/dev/null || true
PID=''
echo 'Linux integration: OK'
