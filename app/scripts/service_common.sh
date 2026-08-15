#!/bin/bash
# Shared service helpers. Apple /bin/bash 3.2 compatible; no user shell rc files.

LT_BASE="${LOCALTUBE_BASE:-$HOME/Library/Application Support/LocalTube}"
LT_LABEL='com.localtube.service'
LT_PLIST="$HOME/Library/LaunchAgents/$LT_LABEL.plist"
LT_UID="$(/usr/bin/id -u)"
LT_DOMAIN="gui/$LT_UID"
LT_DEFAULT_PORT='8765'

lt_port() {
  _lt_p="$LT_DEFAULT_PORT"
  if [ -f "$LT_BASE/data/port" ]; then
    _lt_read="$(/bin/cat "$LT_BASE/data/port" 2>/dev/null | /usr/bin/head -n1 | /usr/bin/tr -cd '0-9')"
    case "$_lt_read" in
      '') ;;
      *) if [ "$_lt_read" -ge 1024 ] 2>/dev/null && [ "$_lt_read" -le 65535 ] 2>/dev/null; then _lt_p="$_lt_read"; fi ;;
    esac
  fi
  printf '%s\n' "$_lt_p"
}

lt_token() {
  [ -f "$LT_BASE/data/api_token" ] || return 1
  /usr/bin/tr -d '\r\n' < "$LT_BASE/data/api_token"
}

lt_health() {
  _lt_port="$(lt_port)"
  _lt_token="$(lt_token 2>/dev/null)" || return 1
  [ -n "$_lt_token" ] || return 1
  /usr/bin/curl -q --noproxy '*' --http1.1 --fail --silent --show-error --max-time 3 \
    -H "X-LocalTube-Token: $_lt_token" \
    "http://127.0.0.1:$_lt_port/api/health" 2>/dev/null | /usr/bin/grep -q '"ok":true'
}

lt_wait_health() {
  _lt_i=0; _lt_limit="${1:-25}"
  while [ "$_lt_i" -lt "$_lt_limit" ]; do
    lt_health && return 0
    /bin/sleep 1
    _lt_i=$((_lt_i + 1))
  done
  return 1
}

lt_has_active_jobs() {
  _lt_port="$(lt_port)"
  _lt_token="$(lt_token 2>/dev/null)" || return 1
  _lt_jobs="$(/usr/bin/curl -q --noproxy '*' --http1.1 --fail --silent --max-time 4 -H "X-LocalTube-Token: $_lt_token" "http://127.0.0.1:$_lt_port/api/jobs" 2>/dev/null)" || return 1
  printf '%s' "$_lt_jobs" | /usr/bin/grep -Eq '"state":"(queued|running)"'
}


lt_loaded() {
  /bin/launchctl print "$LT_DOMAIN/$LT_LABEL" >/dev/null 2>&1
}

lt_wait_unloaded() {
  _lt_i=0; _lt_limit="${1:-12}"
  while [ "$_lt_i" -lt "$_lt_limit" ]; do
    lt_loaded || return 0
    /bin/sleep 1
    _lt_i=$((_lt_i + 1))
  done
  return 1
}
lt_bootout() {
  /bin/launchctl bootout "$LT_DOMAIN/$LT_LABEL" >/dev/null 2>&1 || \
    /bin/launchctl bootout "$LT_DOMAIN" "$LT_PLIST" >/dev/null 2>&1 || true
}

lt_bootstrap() {
  [ -f "$LT_PLIST" ] || return 1
  /bin/launchctl bootstrap "$LT_DOMAIN" "$LT_PLIST" >/dev/null 2>&1 || return 1
  /bin/launchctl enable "$LT_DOMAIN/$LT_LABEL" >/dev/null 2>&1 || true
  /bin/launchctl kickstart -k "$LT_DOMAIN/$LT_LABEL" >/dev/null 2>&1 || true
}

lt_open_ui() {
  /usr/bin/open "http://127.0.0.1:$(lt_port)/" >/dev/null 2>&1 || true
}

lt_has_active_runtime_processes() {
  [ -x /usr/bin/pgrep ] || return 1
  [ -d "$LT_BASE/runtime" ] || return 1
  /usr/bin/pgrep -f "$LT_BASE/runtime/yt-dlp" >/dev/null 2>&1 && return 0
  /usr/bin/pgrep -f "$LT_BASE/runtime/ffmpeg" >/dev/null 2>&1 && return 0
  return 1
}
