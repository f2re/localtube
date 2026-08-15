#!/bin/sh
BASE="$HOME/Library/Application Support/LocalTube"
LABEL='com.localtube.service'; UID_NUM=$(/usr/bin/id -u); DOMAIN="gui/$UID_NUM"; PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
printf '%s\n' 'Удалить LocalTube, его окружение, настройки и историю? Загруженные видео НЕ удаляются.'
printf '%s' 'Для подтверждения введите DELETE: '
IFS= read -r ANSWER
[ "$ANSWER" = 'DELETE' ] || { printf '%s\n' 'Отменено.'; exit 0; }
/bin/launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
/bin/rm -f "$PLIST"
/bin/rm -rf "$BASE" "$HOME/Applications/LocalTube.app" "$HOME/Applications/LocalTube Tools"
printf '%s\n' 'LocalTube удалён. Файлы в папках загрузок сохранены.'
