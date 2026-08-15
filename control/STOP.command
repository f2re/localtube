#!/bin/sh
LABEL='com.localtube.service'; UID_NUM=$(/usr/bin/id -u); DOMAIN="gui/$UID_NUM"
/bin/launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
printf '%s\n' 'LocalTube остановлен. При следующем входе в macOS LaunchAgent снова будет доступен.'
