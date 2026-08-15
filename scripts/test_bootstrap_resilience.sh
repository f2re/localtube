#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
. "$ROOT/app/scripts/runtime_common.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME" "$TMP/bin"
export LOCALTUBE_BOOTSTRAP_CACHE="$TMP/cache"

# 1) Reproduce the Ventura/LibreSSL class of failure deterministically:
# first curl transport fails with code 35, HTTP/1.1 fallback succeeds.
cat > "$TMP/bin/curl" <<'SH'
#!/bin/sh
out=''; http1=0; writeout=0
prev=''
for arg in "$@"; do
  [ "$prev" = '--output' ] && out="$arg"
  [ "$arg" = '--http1.1' ] && http1=1
  [ "$arg" = '--write-out' ] && writeout=1
  prev="$arg"
done
case "$*" in *'--help all'*) printf '%s\n' '--retry-all-errors --tls-max'; exit 0 ;; esac
[ "$http1" -eq 1 ] || exit 35
[ -n "$out" ] || exit 2
printf 'transport-ok\n' > "$out"
[ "$writeout" -eq 1 ] && printf 'https://example.invalid/final'
exit 0
SH
chmod 755 "$TMP/bin/curl"
OLD_PATH="$PATH"
PATH="$TMP/bin:/usr/bin:/bin:/usr/sbin:/sbin"
lt_download 'https://example.invalid/file' "$TMP/download" 'test resilient curl transport'
grep -q transport-ok "$TMP/download"
PATH="$OLD_PATH"

# Keep the test platform deterministic on Linux, Apple Silicon and Intel CI.
lt_os() { printf '%s\n' darwin; }
lt_arch() { printf '%s\n' amd64; }

make_tool() {
  name="$1"; path="$2"
  case "$name" in
    deno) body='echo "deno 2.9.5"' ;;
    yt-dlp) body='echo "2026.08.04"' ;;
    ffmpeg) body='echo "ffmpeg version test"' ;;
    ffprobe) body='echo "ffprobe version test"' ;;
  esac
  printf '#!/bin/sh\n%s\nexit 0\n' "$body" > "$path"
  chmod 755 "$path"
}

mkdir -p "$TMP/seed"
for t in deno yt-dlp ffmpeg ffprobe; do
  make_tool "$t" "$TMP/seed/$t"
  lt_cache_store "$TMP/seed/$t" "$t" "test-seed-$t"
done

# 2) Total network failure must still produce a complete runtime from verified cache.
lt_download() { return 1; }
lt_download_effective() { return 1; }
lt_install_runtime "$TMP/runtime-from-cache"
for t in deno yt-dlp ffmpeg ffprobe; do test -x "$TMP/runtime-from-cache/$t"; done
grep -q 'cache:' "$TMP/runtime-from-cache/manifest.json"

# 3) With an empty cache, a known-good currently installed runtime is the next fallback.
rm -rf "$LOCALTUBE_BOOTSTRAP_CACHE"
mkdir -p "$TMP/existing"
for t in deno yt-dlp ffmpeg ffprobe; do make_tool "$t" "$TMP/existing/$t"; done
export LOCALTUBE_EXISTING_RUNTIME="$TMP/existing"
lt_install_runtime "$TMP/runtime-from-existing"
for t in deno yt-dlp ffmpeg ffprobe; do test -x "$TMP/runtime-from-existing/$t"; done
grep -q 'existing LocalTube runtime' "$TMP/runtime-from-existing/manifest.json"

printf 'bootstrap resilience tests: OK\n'
