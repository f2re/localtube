#!/bin/sh
LABEL='com.localtube.service'; UID_NUM=$(/usr/bin/id -u); DOMAIN="gui/$UID_NUM"
case "${1:-}" in
  --disable)
    /bin/launchctl disable "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
    /bin/launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
    printf '%s
' 'LocalTube остановлен, автозапуск отключён. START.command снова включит его.'
    ;;
  *)
    /bin/launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
    printf '%s
' 'LocalTube остановлен до следующего ручного запуска или входа в macOS.'
    ;;
esac
