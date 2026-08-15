#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT"
echo '[1/8] shell syntax'
/bin/bash -n installer/install.sh app/scripts/*.sh
for f in INSTALL.command control/*.command; do /bin/sh -n "$f"; done

echo '[2/8] TypeScript / JavaScript'
tsc --noEmit --target ES2022 --lib ES2022,DOM --skipLibCheck app/server.ts
node --check app/static/app.js

echo '[3/8] bash-3.2 guard'
python3 scripts/check_shell_compat.py

echo '[4/8] native cross-build + bootstrap package'
python3 scripts/build_release.py >/tmp/localtube-build.txt

echo '[5/8] ZIP structure + executable modes + ASCII command names'
python3 scripts/verify_release.py

echo '[6/8] forbidden-pattern/security regression checks'
python3 scripts/static_audit.py

echo '[7/8] fallback installer isolation'
_tmp_rc="$(mktemp -d)"
printf 'printf BROKEN_PROFILE_WAS_READ\\n' > "$_tmp_rc/evil.sh"
_out="$(ENV="$_tmp_rc/evil.sh" BASH_ENV="$_tmp_rc/evil.sh" ZDOTDIR="$_tmp_rc" ./INSTALL.command --self-test)"
rm -rf "$_tmp_rc"
printf '%s\n' "$_out" | grep -q 'installer self-test: OK'
if printf '%s\n' "$_out" | grep -q 'BROKEN_PROFILE_WAS_READ'; then
  echo 'ERROR: fallback installer sourced hostile shell startup code' >&2
  exit 1
fi

echo '[8/8] source/package version consistency'
V="$(cat app/VERSION)"
grep -q "LocalTube $V" app/server.ts
grep -q "LocalTube $V" installer/install.sh
printf 'LocalTube %s: all local checks passed.\n' "$V"
