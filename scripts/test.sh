#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT"

echo '[1/10] shell syntax'
/bin/bash -n installer/install.sh installer/install-linux.sh app/scripts/*.sh scripts/ci_linux_integration.sh
for f in INSTALL.command control/*.command control/linux/localtube; do /bin/sh -n "$f"; done

echo '[2/10] TypeScript / JavaScript'
tsc --noEmit --target ES2022 --lib ES2022,DOM --skipLibCheck app/server.ts
node --check app/static/app.js

echo '[3/10] Bash 3.2 compatibility'
python3 scripts/check_shell_compat.py

echo '[4/10] Unix runtime destination guard'
_tmp_runtime_test="$(mktemp -d)"
(
  set -e
  . app/scripts/runtime_common.sh
  lt_os() { printf '%s\n' darwin; }
  lt_arch() { printf '%s\n' arm64; }
  lt_mktemp_dir() { mkdir -p "$_tmp_runtime_test/tmp"; printf '%s\n' "$_tmp_runtime_test/tmp"; }
  lt_install_deno() { printf '#!/bin/sh\nexit 0\n' > "$2"; chmod 755 "$2"; }
  lt_download_ytdlp() { printf '#!/bin/sh\nexit 0\n' > "$2"; chmod 755 "$2"; }
  lt_install_ffmpeg_pair() { printf '#!/bin/sh\nexit 0\n' > "$2/ffmpeg"; printf '#!/bin/sh\nexit 0\n' > "$2/ffprobe"; chmod 755 "$2/ffmpeg" "$2/ffprobe"; }
  lt_check_exec() { return 0; }
  lt_runtime_manifest() { : > "$1/manifest.json"; }
  lt_install_runtime "$_tmp_runtime_test/runtime"
  for f in deno yt-dlp ffmpeg ffprobe; do test -f "$_tmp_runtime_test/runtime/$f"; done
)
rm -rf "$_tmp_runtime_test"

echo '[5/10] build all bootstrap packages'
python3 scripts/build_release.py >/tmp/localtube-build.txt

echo '[6/10] verify macOS/Linux/Windows packages'
python3 scripts/verify_release.py

echo '[7/10] security regression checks'
python3 scripts/static_audit.py

echo '[8/10] fallback installer isolation'
_tmp_rc="$(mktemp -d)"
printf 'printf BROKEN_PROFILE_WAS_READ\\n' > "$_tmp_rc/evil.sh"
_out="$(ENV="$_tmp_rc/evil.sh" BASH_ENV="$_tmp_rc/evil.sh" ZDOTDIR="$_tmp_rc" ./INSTALL.command --self-test)"
rm -rf "$_tmp_rc"
printf '%s\n' "$_out" | grep -q 'installer self-test: OK'
! printf '%s\n' "$_out" | grep -q 'BROKEN_PROFILE_WAS_READ'

echo '[9/10] macOS source-checkout installation layout'
if [ "$(uname -s 2>/dev/null || true)" = Darwin ]; then
  _layout_out="$(./INSTALL.command --layout-self-test)"
  printf '%s\n' "$_layout_out"
  printf '%s\n' "$_layout_out" | grep -q 'source-checkout layout self-test: OK'
else
  echo 'SKIP: source-checkout .app synthesis is macOS-specific'
fi

echo '[10/10] version/platform consistency'
V="$(cat app/VERSION)"
grep -q "LocalTube $V" app/server.ts
grep -q "LocalTube $V" installer/install.sh
grep -q "Deno.build" app/server.ts
grep -q "windows" app/scripts/runtime_windows.ps1
grep -q "linux" app/scripts/runtime_common.sh
printf 'LocalTube %s: all local checks passed.\n' "$V"
