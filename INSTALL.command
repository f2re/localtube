#!/bin/sh
# Fallback installer. The primary entry point is "Install LocalTube.app".
# If this file is invoked from zsh, use ./INSTALL.command or an absolute path beginning with /Users/…
SELF_DIR=$(CDPATH= cd -- "$(dirname "$0")" 2>/dev/null && pwd -P) || exit 2
exec /usr/bin/env -i HOME="$HOME" USER="${USER:-}" LOGNAME="${LOGNAME:-${USER:-}}" PATH='/usr/bin:/bin:/usr/sbin:/sbin' \
  /bin/bash --noprofile --norc "$SELF_DIR/installer/install.sh" "${1:---terminal}"
