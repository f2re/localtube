#!/bin/sh
BASE="$HOME/Library/Application Support/LocalTube"
SCRIPT="$BASE/app/scripts/update_runtime.sh"
if [ ! -f "$SCRIPT" ]; then printf '%s\n' 'LocalTube не установлен.' >&2; exit 2; fi
exec /usr/bin/env -i HOME="$HOME" USER="${USER:-}" LOGNAME="${LOGNAME:-${USER:-}}" PATH='/usr/bin:/bin:/usr/sbin:/sbin' LOCALTUBE_BASE="$BASE" \
  /bin/bash --noprofile --norc "$SCRIPT"
