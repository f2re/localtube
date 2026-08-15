#!/bin/bash
# LocalTube runtime bootstrap for macOS and Linux.
# Bash 3.2 compatible; does not source interactive shell profiles.
set +e

LT_SOURCE_DENO='unknown'
LT_SOURCE_YTDLP='unknown'
LT_SOURCE_FFMPEG='unknown'

lt_log() { printf '%s\n' "$*"; }
lt_warn() { printf 'WARN: %s\n' "$*" >&2; }
lt_fail() { printf 'ERROR: %s\n' "$*" >&2; return 1; }

lt_cmd() { command -v "$1" 2>/dev/null; }

lt_os() {
  local _lt_s
  _lt_s="$(uname -s 2>/dev/null || printf unknown)"
  case "$_lt_s" in
    Darwin) printf '%s\n' darwin ;;
    Linux) printf '%s\n' linux ;;
    *) return 1 ;;
  esac
}

lt_arch() {
  local _lt_machine
  _lt_machine="$(uname -m 2>/dev/null || printf unknown)"
  case "$_lt_machine" in
    arm64|aarch64) printf '%s\n' arm64 ;;
    x86_64|amd64) printf '%s\n' amd64 ;;
    *) return 1 ;;
  esac
}

lt_mktemp_dir() {
  mktemp -d -t localtube.XXXXXX 2>/dev/null || mktemp -d 2>/dev/null
}

lt_download() {
  local _lt_url _lt_dst _lt_label _lt_curl
  _lt_url="$1"; _lt_dst="$2"; _lt_label="$3"
  _lt_curl="$(lt_cmd curl)" || { lt_fail 'curl is required'; return 1; }
  lt_log "  -> $_lt_label"
  "$_lt_curl" --fail --location --silent --show-error \
    --retry 4 --retry-delay 2 --connect-timeout 20 --max-time 1200 \
    --proto '=https' --proto-redir '=https' --tlsv1.2 \
    "$_lt_url" --output "$_lt_dst"
}

lt_download_effective() {
  local _lt_url _lt_dst _lt_label _lt_effective_file _lt_curl
  _lt_url="$1"; _lt_dst="$2"; _lt_label="$3"; _lt_effective_file="$4"
  _lt_curl="$(lt_cmd curl)" || { lt_fail 'curl is required'; return 1; }
  lt_log "  -> $_lt_label"
  "$_lt_curl" --fail --location --silent --show-error \
    --retry 4 --retry-delay 2 --connect-timeout 20 --max-time 1200 \
    --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --write-out '%{url_effective}' "$_lt_url" --output "$_lt_dst" > "$_lt_effective_file"
}

lt_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print tolower($1)}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print tolower($1)}'
  else
    lt_fail 'No SHA-256 tool found (shasum/sha256sum)'
    return 1
  fi
}

lt_expected_sha() {
  awk '{ for (i=1;i<=NF;i++) if (length($i)==64 && $i !~ /[^0-9A-Fa-f]/) { print tolower($i); exit } }' "$1"
}

lt_expected_named_sha() {
  local _lt_sums _lt_name
  _lt_sums="$1"; _lt_name="$2"
  awk -v name="$_lt_name" '{
    file=$2; sub(/^\*/, "", file);
    if (file==name) { print tolower($1); exit }
  }' "$_lt_sums"
}

lt_verify_sha_file() {
  local _lt_file _lt_sumfile _lt_label _lt_expected _lt_actual
  _lt_file="$1"; _lt_sumfile="$2"; _lt_label="$3"
  _lt_expected="$(lt_expected_sha "$_lt_sumfile")"
  _lt_actual="$(lt_sha256 "$_lt_file")" || return 1
  if [ -z "$_lt_expected" ] || [ "$_lt_expected" != "$_lt_actual" ]; then
    lt_fail "SHA-256 mismatch for $_lt_label"
    return 1
  fi
  lt_log '     SHA-256 OK'
}

lt_verify_named_sha() {
  local _lt_file _lt_sums _lt_asset _lt_label _lt_expected _lt_actual
  _lt_file="$1"; _lt_sums="$2"; _lt_asset="$3"; _lt_label="$4"
  _lt_expected="$(lt_expected_named_sha "$_lt_sums" "$_lt_asset")"
  _lt_actual="$(lt_sha256 "$_lt_file")" || return 1
  if [ -z "$_lt_expected" ] || [ "$_lt_expected" != "$_lt_actual" ]; then
    lt_fail "SHA-256 mismatch for $_lt_label"
    return 1
  fi
  lt_log '     SHA-256 OK'
}

lt_extract_named() {
  local _lt_zip _lt_name _lt_dst _lt_tmp _lt_extract _lt_found _lt_unzip
  _lt_zip="$1"; _lt_name="$2"; _lt_dst="$3"; _lt_tmp="$4"
  _lt_unzip="$(lt_cmd unzip)" || { lt_fail 'unzip is required'; return 1; }
  _lt_extract="$_lt_tmp/extract-$_lt_name"
  rm -rf "$_lt_extract"; mkdir -p "$_lt_extract"
  "$_lt_unzip" -qq "$_lt_zip" -d "$_lt_extract" || return 1
  _lt_found="$(find "$_lt_extract" -type f -name "$_lt_name" -print 2>/dev/null | head -n 1)"
  [ -n "$_lt_found" ] || { lt_fail "$_lt_name was not found inside downloaded archive"; return 1; }
  cp "$_lt_found" "$_lt_dst" || return 1
  chmod 755 "$_lt_dst"
}

lt_check_exec() {
  local _lt_file _lt_label
  _lt_file="$1"; _lt_label="$2"; shift 2
  [ -x "$_lt_file" ] || { lt_fail "$_lt_label is not executable: $_lt_file"; return 1; }
  "$_lt_file" "$@" >/dev/null 2>&1 || { lt_fail "$_lt_label failed its self-check"; return 1; }
}

lt_version_ge() {
  local _lt_actual _lt_required
  _lt_actual="$1"; _lt_required="$2"
  awk -v a="$_lt_actual" -v r="$_lt_required" 'BEGIN {
    na=split(a,A,"."); nr=split(r,R,"."); n=(na>nr?na:nr);
    for(i=1;i<=n;i++){ av=(A[i]+0); rv=(R[i]+0); if(av>rv) exit 0; if(av<rv) exit 1; }
    exit 0
  }'
}

lt_check_deno_version() {
  local _lt_file _lt_line _lt_ver
  _lt_file="$1"
  _lt_line="$("$_lt_file" --version 2>/dev/null | head -n 1)"
  _lt_ver="$(printf '%s\n' "$_lt_line" | awk '{print $2}')"
  [ -n "$_lt_ver" ] && lt_version_ge "$_lt_ver" '2.3.0'
}

lt_find_external() {
  local _lt_tool _lt_found _lt_candidate
  _lt_tool="$1"
  _lt_found="$(command -v "$_lt_tool" 2>/dev/null)"
  if [ -n "$_lt_found" ] && [ -x "$_lt_found" ]; then printf '%s\n' "$_lt_found"; return 0; fi
  for _lt_candidate in \
    "/opt/homebrew/bin/$_lt_tool" "/usr/local/bin/$_lt_tool" "/opt/local/bin/$_lt_tool" \
    "$HOME/.deno/bin/$_lt_tool" "$HOME/.local/bin/$_lt_tool" "/usr/bin/$_lt_tool" "/bin/$_lt_tool"; do
    if [ -x "$_lt_candidate" ]; then printf '%s\n' "$_lt_candidate"; return 0; fi
  done
  return 1
}

lt_make_wrapper() {
  local _lt_dest _lt_target _lt_name
  _lt_dest="$1"; _lt_target="$2"; _lt_name="$3"
  case "$_lt_target" in *'"'*|*$'\n'*) return 1 ;; esac
  cat > "$_lt_dest" <<WRAP
#!/bin/sh
# LOCALTUBE_EXTERNAL_TOOL=$_lt_name
exec "$_lt_target" "\$@"
WRAP
  chmod 755 "$_lt_dest"
}

lt_runtime_manifest() {
  local _lt_runtime _lt_deno_v _lt_ytdlp_v _lt_ffmpeg_v _lt_arch _lt_os
  _lt_runtime="$1"
  _lt_deno_v="$("$_lt_runtime/deno" --version 2>/dev/null | head -n1 | sed 's/"/\\"/g')"
  _lt_ytdlp_v="$("$_lt_runtime/yt-dlp" --version 2>/dev/null | head -n1 | sed 's/"/\\"/g')"
  _lt_ffmpeg_v="$("$_lt_runtime/ffmpeg" -version 2>/dev/null | head -n1 | sed 's/"/\\"/g')"
  _lt_arch="$(lt_arch)"; _lt_os="$(lt_os)"
  cat > "$_lt_runtime/manifest.json" <<JSON
{
  "installed_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "platform": "$_lt_os",
  "architecture": "$_lt_arch",
  "deno": "$_lt_deno_v",
  "deno_source": "$LT_SOURCE_DENO",
  "yt_dlp": "$_lt_ytdlp_v",
  "yt_dlp_source": "$LT_SOURCE_YTDLP",
  "ffmpeg": "$_lt_ffmpeg_v",
  "ffmpeg_source": "$LT_SOURCE_FFMPEG"
}
JSON
  chmod 600 "$_lt_runtime/manifest.json" >/dev/null 2>&1 || true
}

lt_install_deno() {
  local _lt_tmp _lt_dest _lt_arch _lt_os _lt_asset _lt_zip _lt_sum _lt_external
  _lt_tmp="$1"; _lt_dest="$2"; _lt_arch="$3"; _lt_os="$(lt_os)" || return 1
  case "$_lt_os:$_lt_arch" in
    darwin:arm64) _lt_asset='deno-aarch64-apple-darwin.zip' ;;
    darwin:amd64) _lt_asset='deno-x86_64-apple-darwin.zip' ;;
    linux:arm64) _lt_asset='deno-aarch64-unknown-linux-gnu.zip' ;;
    linux:amd64) _lt_asset='deno-x86_64-unknown-linux-gnu.zip' ;;
    *) return 1 ;;
  esac
  _lt_zip="$_lt_tmp/$_lt_asset"; _lt_sum="$_lt_tmp/$_lt_asset.sha256sum"
  if lt_download "https://github.com/denoland/deno/releases/latest/download/$_lt_asset" "$_lt_zip" 'downloading official Deno' && \
     lt_download "https://github.com/denoland/deno/releases/latest/download/$_lt_asset.sha256sum" "$_lt_sum" 'downloading Deno checksum' && \
     lt_verify_sha_file "$_lt_zip" "$_lt_sum" Deno && \
     lt_extract_named "$_lt_zip" deno "$_lt_dest" "$_lt_tmp" && \
     lt_check_exec "$_lt_dest" Deno --version && lt_check_deno_version "$_lt_dest"; then
    LT_SOURCE_DENO='github.com/denoland/deno release + SHA-256'
    return 0
  fi
  lt_warn 'Official Deno download failed; checking an existing local Deno installation.'
  _lt_external="$(lt_find_external deno 2>/dev/null)" || return 1
  lt_check_deno_version "$_lt_external" || { lt_warn 'Existing Deno is older than 2.3.0.'; return 1; }
  lt_make_wrapper "$_lt_dest" "$_lt_external" deno || return 1
  lt_check_exec "$_lt_dest" Deno --version || return 1
  LT_SOURCE_DENO="external:$_lt_external"
}

lt_download_ytdlp() {
  local _lt_tmp _lt_dest _lt_arch _lt_os _lt_asset _lt_ytdlp _lt_sums _lt_base _lt_external
  _lt_tmp="$1"; _lt_dest="$2"; _lt_arch="$3"; _lt_os="$(lt_os)" || return 1
  case "$_lt_os:$_lt_arch" in
    darwin:*) _lt_asset='yt-dlp_macos' ;;
    linux:amd64) _lt_asset='yt-dlp_linux' ;;
    linux:arm64) _lt_asset='yt-dlp_linux_aarch64' ;;
    *) return 1 ;;
  esac
  _lt_ytdlp="$_lt_tmp/$_lt_asset"; _lt_sums="$_lt_tmp/SHA2-256SUMS"
  for _lt_base in \
    'https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download' \
    'https://github.com/yt-dlp/yt-dlp/releases/latest/download'; do
    rm -f "$_lt_ytdlp" "$_lt_sums"
    if lt_download "$_lt_base/$_lt_asset" "$_lt_ytdlp" "downloading yt-dlp ($_lt_asset)" && \
       lt_download "$_lt_base/SHA2-256SUMS" "$_lt_sums" 'downloading yt-dlp checksums' && \
       lt_verify_named_sha "$_lt_ytdlp" "$_lt_sums" "$_lt_asset" yt-dlp; then
      cp "$_lt_ytdlp" "$_lt_dest"; chmod 755 "$_lt_dest"
      LT_SOURCE_YTDLP="$_lt_base + SHA-256"
      return 0
    fi
  done
  lt_warn 'Official yt-dlp downloads failed; checking an existing local yt-dlp installation.'
  _lt_external="$(lt_find_external yt-dlp 2>/dev/null)" || return 1
  lt_make_wrapper "$_lt_dest" "$_lt_external" yt-dlp || return 1
  lt_check_exec "$_lt_dest" yt-dlp --version || return 1
  LT_SOURCE_YTDLP="external:$_lt_external"
}

lt_install_ffmpeg_macos() {
  local _lt_tmp _lt_dest _lt_arch _lt_ffarch _lt_tool _lt_zip _lt_sum _lt_base _lt_effective_file _lt_effective
  _lt_tmp="$1"; _lt_dest="$2"; _lt_arch="$3"
  case "$_lt_arch" in arm64) _lt_ffarch='arm64' ;; amd64) _lt_ffarch='amd64' ;; *) return 1 ;; esac
  for _lt_tool in ffmpeg ffprobe; do
    _lt_zip="$_lt_tmp/$_lt_tool.zip"; _lt_sum="$_lt_tmp/$_lt_tool.zip.sha256"
    _lt_effective_file="$_lt_tmp/$_lt_tool.effective-url"
    _lt_base="https://ffmpeg.martin-riedl.de/redirect/latest/macos/$_lt_ffarch/release/$_lt_tool.zip"
    lt_download_effective "$_lt_base" "$_lt_zip" "downloading signed macOS $_lt_tool" "$_lt_effective_file" || return 1
    _lt_effective="$(tr -d '\r\n' < "$_lt_effective_file")"
    case "$_lt_effective" in https://ffmpeg.martin-riedl.de/download/*/"$_lt_tool".zip) ;; *) return 1 ;; esac
    lt_download "$_lt_effective.sha256" "$_lt_sum" "downloading $_lt_tool checksum" || return 1
    lt_verify_sha_file "$_lt_zip" "$_lt_sum" "$_lt_tool" || return 1
    lt_extract_named "$_lt_zip" "$_lt_tool" "$_lt_dest/$_lt_tool" "$_lt_tmp" || return 1
  done
  LT_SOURCE_FFMPEG='ffmpeg.martin-riedl.de signed release builds + SHA-256'
}

lt_install_ffmpeg_linux() {
  local _lt_tmp _lt_dest _lt_arch _lt_asset _lt_archive _lt_sums _lt_extract _lt_ffmpeg _lt_ffprobe
  _lt_tmp="$1"; _lt_dest="$2"; _lt_arch="$3"
  case "$_lt_arch" in
    amd64) _lt_asset='ffmpeg-master-latest-linux64-gpl.tar.xz' ;;
    arm64) _lt_asset='ffmpeg-master-latest-linuxarm64-gpl.tar.xz' ;;
    *) return 1 ;;
  esac
  _lt_archive="$_lt_tmp/$_lt_asset"; _lt_sums="$_lt_tmp/checksums.sha256"; _lt_extract="$_lt_tmp/ffmpeg-linux"
  lt_download "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/$_lt_asset" "$_lt_archive" 'downloading FFmpeg static build' || return 1
  lt_download 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/checksums.sha256' "$_lt_sums" 'downloading FFmpeg checksums' || return 1
  lt_verify_named_sha "$_lt_archive" "$_lt_sums" "$_lt_asset" FFmpeg || return 1
  mkdir -p "$_lt_extract"
  tar -xJf "$_lt_archive" -C "$_lt_extract" || return 1
  _lt_ffmpeg="$(find "$_lt_extract" -type f -path '*/bin/ffmpeg' -print | head -n1)"
  _lt_ffprobe="$(find "$_lt_extract" -type f -path '*/bin/ffprobe' -print | head -n1)"
  [ -n "$_lt_ffmpeg" ] && [ -n "$_lt_ffprobe" ] || return 1
  cp "$_lt_ffmpeg" "$_lt_dest/ffmpeg" || return 1
  cp "$_lt_ffprobe" "$_lt_dest/ffprobe" || return 1
  chmod 755 "$_lt_dest/ffmpeg" "$_lt_dest/ffprobe"
  LT_SOURCE_FFMPEG='github.com/BtbN/FFmpeg-Builds latest + SHA-256'
}

lt_install_ffmpeg_pair() {
  local _lt_tmp _lt_dest _lt_arch _lt_os _lt_ffmpeg _lt_ffprobe
  _lt_tmp="$1"; _lt_dest="$2"; _lt_arch="$3"; _lt_os="$(lt_os)" || return 1
  if [ "$_lt_os" = darwin ]; then
    lt_install_ffmpeg_macos "$_lt_tmp" "$_lt_dest" "$_lt_arch"
  else
    lt_install_ffmpeg_linux "$_lt_tmp" "$_lt_dest" "$_lt_arch"
  fi
  if [ $? -eq 0 ] && lt_check_exec "$_lt_dest/ffmpeg" FFmpeg -version && lt_check_exec "$_lt_dest/ffprobe" FFprobe -version; then
    return 0
  fi
  lt_warn 'Bundled FFmpeg download failed; checking an existing local FFmpeg installation.'
  rm -f "$_lt_dest/ffmpeg" "$_lt_dest/ffprobe"
  _lt_ffmpeg="$(lt_find_external ffmpeg 2>/dev/null)" || return 1
  _lt_ffprobe="$(lt_find_external ffprobe 2>/dev/null)" || return 1
  lt_make_wrapper "$_lt_dest/ffmpeg" "$_lt_ffmpeg" ffmpeg || return 1
  lt_make_wrapper "$_lt_dest/ffprobe" "$_lt_ffprobe" ffprobe || return 1
  lt_check_exec "$_lt_dest/ffmpeg" FFmpeg -version || return 1
  lt_check_exec "$_lt_dest/ffprobe" FFprobe -version || return 1
  LT_SOURCE_FFMPEG="external:$_lt_ffmpeg;$_lt_ffprobe"
}

lt_install_runtime() {
  local _lt_runtime _lt_arch _lt_tmp _lt_stage
  _lt_runtime="$1"
  _lt_arch="$(lt_arch)" || { lt_fail 'Unsupported CPU architecture'; return 1; }
  lt_os >/dev/null 2>&1 || { lt_fail 'Unsupported OS; shell bootstrap supports macOS and Linux'; return 1; }
  _lt_tmp="$(lt_mktemp_dir)" || return 1
  _lt_stage="$_lt_tmp/runtime"
  mkdir -p "$_lt_stage" || { rm -rf "$_lt_tmp"; return 1; }

  lt_log '[runtime 1/4] Deno >= 2.3'
  lt_install_deno "$_lt_tmp" "$_lt_stage/deno" "$_lt_arch" || { rm -rf "$_lt_tmp"; return 1; }
  lt_log '[runtime 2/4] yt-dlp'
  lt_download_ytdlp "$_lt_tmp" "$_lt_stage/yt-dlp" "$_lt_arch" || { rm -rf "$_lt_tmp"; return 1; }
  lt_log '[runtime 3/4] FFmpeg + FFprobe'
  lt_install_ffmpeg_pair "$_lt_tmp" "$_lt_stage" "$_lt_arch" || { rm -rf "$_lt_tmp"; return 1; }
  lt_log '[runtime 4/4] executable self-tests'
  lt_check_exec "$_lt_stage/deno" Deno --version || { rm -rf "$_lt_tmp"; return 1; }
  lt_check_exec "$_lt_stage/yt-dlp" yt-dlp --version || { rm -rf "$_lt_tmp"; return 1; }
  lt_check_exec "$_lt_stage/ffmpeg" FFmpeg -version || { rm -rf "$_lt_tmp"; return 1; }
  lt_check_exec "$_lt_stage/ffprobe" FFprobe -version || { rm -rf "$_lt_tmp"; return 1; }
  lt_runtime_manifest "$_lt_stage" || { rm -rf "$_lt_tmp"; return 1; }

  rm -rf "$_lt_runtime.new"
  mv "$_lt_stage" "$_lt_runtime.new" || { rm -rf "$_lt_tmp"; return 1; }
  rm -rf "$_lt_runtime"
  mv "$_lt_runtime.new" "$_lt_runtime" || { rm -rf "$_lt_tmp"; return 1; }
  rm -rf "$_lt_tmp"
}
