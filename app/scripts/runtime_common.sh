#!/bin/bash
# LocalTube runtime bootstrap — compatible with Apple's /bin/bash 3.2.
# Does not source ~/.zshrc, ~/.bashrc, Oh-My-Zsh, Homebrew shellenv, pyenv, etc.
set +e

LT_SOURCE_DENO='unknown'
LT_SOURCE_YTDLP='unknown'
LT_SOURCE_FFMPEG='unknown'

lt_log() { printf '%s\n' "$*"; }
lt_warn() { printf 'WARN: %s\n' "$*" >&2; }
lt_fail() { printf 'ERROR: %s\n' "$*" >&2; return 1; }

lt_arch() {
  local _lt_machine
  _lt_machine="$(/usr/bin/uname -m 2>/dev/null || uname -m)"
  case "$_lt_machine" in
    arm64|aarch64) printf '%s\n' arm64 ;;
    x86_64|amd64) printf '%s\n' amd64 ;;
    *) return 1 ;;
  esac
}

lt_mktemp_dir() {
  /usr/bin/mktemp -d -t localtube.XXXXXX 2>/dev/null || /usr/bin/mktemp -d 2>/dev/null || mktemp -d
}

lt_download() {
  local _lt_url _lt_dst _lt_label
  _lt_url="$1"; _lt_dst="$2"; _lt_label="$3"
  lt_log "  -> $_lt_label"
  /usr/bin/curl --fail --location --silent --show-error \
    --retry 4 --retry-delay 2 \
    --connect-timeout 20 --max-time 1200 \
    --proto '=https' --proto-redir '=https' --tlsv1.2 "$_lt_url" --output "$_lt_dst"
}

lt_download_effective() {
  local _lt_url _lt_dst _lt_label _lt_effective_file
  _lt_url="$1"; _lt_dst="$2"; _lt_label="$3"; _lt_effective_file="$4"
  lt_log "  -> $_lt_label"
  /usr/bin/curl --fail --location --silent --show-error \
    --retry 4 --retry-delay 2 \
    --connect-timeout 20 --max-time 1200 \
    --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --write-out '%{url_effective}' "$_lt_url" --output "$_lt_dst" > "$_lt_effective_file"
}

lt_sha256() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print tolower($1)}'
}

lt_expected_sha() {
  /usr/bin/awk '{ for (i=1;i<=NF;i++) if (length($i)==64 && $i !~ /[^0-9A-Fa-f]/) { print tolower($i); exit } }' "$1"
}

lt_verify_sha_file() {
  local _lt_file _lt_sumfile _lt_label _lt_expected _lt_actual
  _lt_file="$1"; _lt_sumfile="$2"; _lt_label="$3"
  _lt_expected="$(lt_expected_sha "$_lt_sumfile")"
  _lt_actual="$(lt_sha256 "$_lt_file")"
  if [ -z "$_lt_expected" ] || [ "$_lt_expected" != "$_lt_actual" ]; then
    lt_fail "SHA-256 mismatch for $_lt_label"
    return 1
  fi
  lt_log '     SHA-256 OK'
}

lt_verify_ytdlp() {
  local _lt_file _lt_sums _lt_expected _lt_actual
  _lt_file="$1"; _lt_sums="$2"
  _lt_expected="$(/usr/bin/awk '$2=="yt-dlp_macos" || $2=="*yt-dlp_macos" {print tolower($1); exit}' "$_lt_sums")"
  _lt_actual="$(lt_sha256 "$_lt_file")"
  if [ -z "$_lt_expected" ] || [ "$_lt_expected" != "$_lt_actual" ]; then
    lt_fail 'SHA-256 mismatch for yt-dlp_macos'
    return 1
  fi
  lt_log '     SHA-256 OK'
}

lt_extract_named() {
  local _lt_zip _lt_name _lt_dst _lt_tmp _lt_extract _lt_found
  _lt_zip="$1"; _lt_name="$2"; _lt_dst="$3"; _lt_tmp="$4"
  _lt_extract="$_lt_tmp/extract-$_lt_name"
  /bin/rm -rf "$_lt_extract"; /bin/mkdir -p "$_lt_extract"
  /usr/bin/unzip -qq "$_lt_zip" -d "$_lt_extract" || return 1
  _lt_found="$(/usr/bin/find "$_lt_extract" -type f -name "$_lt_name" -print 2>/dev/null | /usr/bin/head -n 1)"
  [ -n "$_lt_found" ] || { lt_fail "$_lt_name was not found inside downloaded archive"; return 1; }
  /bin/cp "$_lt_found" "$_lt_dst" || return 1
  /bin/chmod 755 "$_lt_dst"
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
  /usr/bin/awk -v a="$_lt_actual" -v r="$_lt_required" 'BEGIN {
    na=split(a,A,"."); nr=split(r,R,"."); n=(na>nr?na:nr);
    for(i=1;i<=n;i++){ av=(A[i]+0); rv=(R[i]+0); if(av>rv) exit 0; if(av<rv) exit 1; }
    exit 0
  }'
}

lt_check_deno_version() {
  local _lt_file _lt_line _lt_ver
  _lt_file="$1"
  _lt_line="$("$_lt_file" --version 2>/dev/null | /usr/bin/head -n 1)"
  _lt_ver="$(printf '%s\n' "$_lt_line" | /usr/bin/awk '{print $2}')"
  [ -n "$_lt_ver" ] && lt_version_ge "$_lt_ver" '2.3.0'
}

lt_find_external() {
  local _lt_tool _lt_candidate
  _lt_tool="$1"
  for _lt_candidate in \
    "/opt/homebrew/bin/$_lt_tool" \
    "/usr/local/bin/$_lt_tool" \
    "/opt/local/bin/$_lt_tool" \
    "$HOME/.deno/bin/$_lt_tool" \
    "$HOME/.local/bin/$_lt_tool"; do
    if [ -x "$_lt_candidate" ]; then printf '%s\n' "$_lt_candidate"; return 0; fi
  done
  return 1
}

lt_make_wrapper() {
  local _lt_dest _lt_target _lt_name
  _lt_dest="$1"; _lt_target="$2"; _lt_name="$3"
  case "$_lt_target" in *'"'*|*$'\n'*) return 1 ;; esac
  /bin/cat > "$_lt_dest" <<WRAP
#!/bin/sh
# LOCALTUBE_EXTERNAL_TOOL=$_lt_name
exec "$_lt_target" "\$@"
WRAP
  /bin/chmod 755 "$_lt_dest"
}

lt_runtime_manifest() {
  local _lt_runtime _lt_deno_v _lt_ytdlp_v _lt_ffmpeg_v _lt_arch
  _lt_runtime="$1"
  _lt_deno_v="$("$_lt_runtime/deno" --version 2>/dev/null | /usr/bin/head -n1 | /usr/bin/sed 's/"/\\"/g')"
  _lt_ytdlp_v="$("$_lt_runtime/yt-dlp" --version 2>/dev/null | /usr/bin/head -n1 | /usr/bin/sed 's/"/\\"/g')"
  _lt_ffmpeg_v="$("$_lt_runtime/ffmpeg" -version 2>/dev/null | /usr/bin/head -n1 | /usr/bin/sed 's/"/\\"/g')"
  _lt_arch="$(lt_arch)"
  cat > "$_lt_runtime/manifest.json" <<JSON
{
  "installed_at": "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "architecture": "$_lt_arch",
  "deno": "$_lt_deno_v",
  "deno_source": "$LT_SOURCE_DENO",
  "yt_dlp": "$_lt_ytdlp_v",
  "yt_dlp_source": "$LT_SOURCE_YTDLP",
  "ffmpeg": "$_lt_ffmpeg_v",
  "ffmpeg_source": "$LT_SOURCE_FFMPEG"
}
JSON
  /bin/chmod 600 "$_lt_runtime/manifest.json" >/dev/null 2>&1 || true
}

lt_install_deno() {
  local _lt_tmp _lt_dest _lt_arch _lt_asset _lt_zip _lt_sum _lt_external
  _lt_tmp="$1"; _lt_dest="$2"; _lt_arch="$3"
  case "$_lt_arch" in
    arm64) _lt_asset='deno-aarch64-apple-darwin.zip' ;;
    amd64) _lt_asset='deno-x86_64-apple-darwin.zip' ;;
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
  return 0
}

lt_download_ytdlp() {
  local _lt_tmp _lt_dest _lt_ytdlp _lt_sums _lt_base _lt_external
  _lt_tmp="$1"; _lt_dest="$2"
  _lt_ytdlp="$_lt_tmp/yt-dlp_macos"; _lt_sums="$_lt_tmp/SHA2-256SUMS"

  _lt_base='https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download'
  if lt_download "$_lt_base/yt-dlp_macos" "$_lt_ytdlp" 'downloading official yt-dlp nightly for macOS' && \
     lt_download "$_lt_base/SHA2-256SUMS" "$_lt_sums" 'downloading yt-dlp nightly checksums' && \
     lt_verify_ytdlp "$_lt_ytdlp" "$_lt_sums"; then
    /bin/cp "$_lt_ytdlp" "$_lt_dest"; /bin/chmod 755 "$_lt_dest"
    LT_SOURCE_YTDLP='github.com/yt-dlp/yt-dlp-nightly-builds + SHA-256'
    return 0
  fi

  lt_warn 'Nightly download failed; retrying with the official stable release.'
  /bin/rm -f "$_lt_ytdlp" "$_lt_sums"
  _lt_base='https://github.com/yt-dlp/yt-dlp/releases/latest/download'
  if lt_download "$_lt_base/yt-dlp_macos" "$_lt_ytdlp" 'downloading official yt-dlp stable for macOS' && \
     lt_download "$_lt_base/SHA2-256SUMS" "$_lt_sums" 'downloading yt-dlp stable checksums' && \
     lt_verify_ytdlp "$_lt_ytdlp" "$_lt_sums"; then
    /bin/cp "$_lt_ytdlp" "$_lt_dest"; /bin/chmod 755 "$_lt_dest"
    LT_SOURCE_YTDLP='github.com/yt-dlp/yt-dlp stable + SHA-256'
    return 0
  fi

  lt_warn 'Official yt-dlp downloads failed; checking an existing local yt-dlp installation.'
  _lt_external="$(lt_find_external yt-dlp 2>/dev/null)" || return 1
  lt_make_wrapper "$_lt_dest" "$_lt_external" yt-dlp || return 1
  lt_check_exec "$_lt_dest" yt-dlp --version || return 1
  LT_SOURCE_YTDLP="external:$_lt_external"
  return 0
}

lt_install_ffmpeg_pair() {
  local _lt_tmp _lt_dest _lt_arch _lt_ffarch _lt_remote_ok _lt_tool _lt_zip _lt_sum _lt_base _lt_effective_file _lt_effective _lt_ffmpeg _lt_ffprobe
  _lt_tmp="$1"; _lt_dest="$2"; _lt_arch="$3"
  case "$_lt_arch" in arm64) _lt_ffarch='arm64' ;; amd64) _lt_ffarch='amd64' ;; *) return 1 ;; esac

  _lt_remote_ok=1
  for _lt_tool in ffmpeg ffprobe; do
    _lt_zip="$_lt_tmp/$_lt_tool.zip"; _lt_sum="$_lt_tmp/$_lt_tool.zip.sha256"
    _lt_effective_file="$_lt_tmp/$_lt_tool.effective-url"
    _lt_base="https://ffmpeg.martin-riedl.de/redirect/latest/macos/$_lt_ffarch/release/$_lt_tool.zip"
    if ! lt_download_effective "$_lt_base" "$_lt_zip" "downloading signed macOS $_lt_tool" "$_lt_effective_file"; then
      _lt_remote_ok=0
      break
    fi
    _lt_effective="$(/usr/bin/tr -d '\r\n' < "$_lt_effective_file")"
    case "$_lt_effective" in https://ffmpeg.martin-riedl.de/download/*/$_lt_tool.zip) ;; *)
      lt_warn "Unexpected FFmpeg redirect target: $_lt_effective"
      _lt_remote_ok=0
      break
    esac
    if ! lt_download "$_lt_effective.sha256" "$_lt_sum" "downloading $_lt_tool checksum" || \
       ! lt_verify_sha_file "$_lt_zip" "$_lt_sum" "$_lt_tool" || \
       ! lt_extract_named "$_lt_zip" "$_lt_tool" "$_lt_dest/$_lt_tool" "$_lt_tmp"; then
      _lt_remote_ok=0
      break
    fi
  done
  if [ "$_lt_remote_ok" -eq 1 ] && \
     lt_check_exec "$_lt_dest/ffmpeg" FFmpeg -version && \
     lt_check_exec "$_lt_dest/ffprobe" FFprobe -version; then
    LT_SOURCE_FFMPEG='ffmpeg.martin-riedl.de signed release builds + SHA-256'
    return 0
  fi

  lt_warn 'FFmpeg build download failed; checking Homebrew/MacPorts/local FFmpeg.'
  /bin/rm -f "$_lt_dest/ffmpeg" "$_lt_dest/ffprobe"
  _lt_ffmpeg="$(lt_find_external ffmpeg 2>/dev/null)" || return 1
  _lt_ffprobe="$(lt_find_external ffprobe 2>/dev/null)" || return 1
  lt_make_wrapper "$_lt_dest/ffmpeg" "$_lt_ffmpeg" ffmpeg || return 1
  lt_make_wrapper "$_lt_dest/ffprobe" "$_lt_ffprobe" ffprobe || return 1
  lt_check_exec "$_lt_dest/ffmpeg" FFmpeg -version || return 1
  lt_check_exec "$_lt_dest/ffprobe" FFprobe -version || return 1
  LT_SOURCE_FFMPEG="external:$_lt_ffmpeg + $_lt_ffprobe"
  return 0
}

lt_install_runtime() {
  local _lt_dest _lt_arch _lt_tmp
  _lt_dest="$1"
  _lt_arch="$(lt_arch)" || { lt_fail "Unsupported CPU architecture: $(uname -m)"; return 1; }
  _lt_tmp="$(lt_mktemp_dir)" || { lt_fail 'Cannot create temporary directory'; return 1; }
  /bin/rm -rf "$_lt_dest"; /bin/mkdir -p "$_lt_dest" || { /bin/rm -rf "$_lt_tmp"; return 1; }

  lt_log '[runtime 1/4] Deno >= 2.3'
  lt_install_deno "$_lt_tmp" "$_lt_dest/deno" "$_lt_arch" || { /bin/rm -rf "$_lt_tmp"; return 1; }

  lt_log '[runtime 2/4] yt-dlp'
  lt_download_ytdlp "$_lt_tmp" "$_lt_dest/yt-dlp" || { /bin/rm -rf "$_lt_tmp"; return 1; }

  lt_log '[runtime 3/4] FFmpeg + FFprobe'
  lt_install_ffmpeg_pair "$_lt_tmp" "$_lt_dest" "$_lt_arch" || { /bin/rm -rf "$_lt_tmp"; return 1; }

  # Files copied from a quarantined ZIP or browser download may inherit quarantine. All directly
  # downloaded runtime artifacts above have been SHA-256 verified before this attribute is removed.
  /usr/bin/xattr -dr com.apple.quarantine "$_lt_dest" >/dev/null 2>&1 || true

  lt_log '[runtime 4/4] executable self-tests'
  lt_check_exec "$_lt_dest/deno" Deno --version || { /bin/rm -rf "$_lt_tmp"; return 1; }
  lt_check_deno_version "$_lt_dest/deno" || { lt_fail 'Deno 2.3.0 or newer is required'; /bin/rm -rf "$_lt_tmp"; return 1; }
  lt_check_exec "$_lt_dest/yt-dlp" yt-dlp --version || { /bin/rm -rf "$_lt_tmp"; return 1; }
  lt_check_exec "$_lt_dest/ffmpeg" FFmpeg -version || { /bin/rm -rf "$_lt_tmp"; return 1; }
  lt_check_exec "$_lt_dest/ffprobe" FFprobe -version || { /bin/rm -rf "$_lt_tmp"; return 1; }

  lt_runtime_manifest "$_lt_dest"
  /bin/rm -rf "$_lt_tmp"
  return 0
}
