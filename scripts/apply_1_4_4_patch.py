#!/usr/bin/env python3
from pathlib import Path


def read(path):
    return Path(path).read_text(encoding='utf-8')

def write(path, text):
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding='utf-8')

def replace_once(path, old, new):
    text = read(path)
    if old not in text:
        raise SystemExit(f'pattern not found in {path}: {old[:160]!r}')
    write(path, text.replace(old, new, 1))

# ---- version ----
write('app/VERSION', '1.4.4\n')
replace_once('app/server.ts', '// LocalTube 1.4.3 — dependency-free cross-platform Deno backend.', '// LocalTube 1.4.4 — dependency-free cross-platform Deno backend.')
replace_once('installer/install.sh', '# LocalTube 1.4.3 macOS installer.', '# LocalTube 1.4.4 macOS installer.')
replace_once('installer/install.sh', "say 'LocalTube 1.4.3 — production installer'", "say 'LocalTube 1.4.4 — production installer'")
replace_once('app/scripts/runtime_common.sh', 'LocalTube-bootstrap/1.4.3', 'LocalTube-bootstrap/1.4.4')

# ---- backend progress model ----
p = Path('app/server.ts')
text = p.read_text(encoding='utf-8')
text = text.replace(
"  eta: string;\n  phase: string;",
"  eta: string;\n  downloaded_bytes: number;\n  total_bytes: number;\n  total_is_estimate: boolean;\n  final_size_bytes: number;\n  current_file: string;\n  postprocessing: boolean;\n  progress_parts: Record<string, { downloaded: number; total: number; estimated: boolean }>;\n  phase: string;",
1)
text = text.replace(
"function delay(ms: number): Promise<void> { return new Promise((resolve) => setTimeout(resolve, ms)); }",
"""function delay(ms: number): Promise<void> { return new Promise((resolve) => setTimeout(resolve, ms)); }
function rawNumber(v: string): number | null {
  const n = Number(v);
  return Number.isFinite(n) && n >= 0 ? n : null;
}
function formatRate(bytesPerSecond: number | null): string {
  if (bytesPerSecond === null || bytesPerSecond <= 0) return '';
  const units = ['Б/с', 'КиБ/с', 'МиБ/с', 'ГиБ/с'];
  let v = bytesPerSecond; let i = 0;
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
  return `${v >= 10 || i === 0 ? v.toFixed(0) : v.toFixed(1)} ${units[i]}`;
}
function formatEtaSeconds(seconds: number | null): string {
  if (seconds === null || seconds < 0) return '';
  const s = Math.round(seconds);
  if (s < 60) return `${s}с`;
  const m = Math.floor(s / 60); const rs = s % 60;
  if (m < 60) return `${m}м ${String(rs).padStart(2, '0')}с`;
  const h = Math.floor(m / 60); return `${h}ч ${String(m % 60).padStart(2, '0')}м`;
}""",
1)
text = text.replace(
"async function ensureDir(path: string): Promise<void> { await Deno.mkdir(path, { recursive: true }); }",
"""async function ensureDir(path: string): Promise<void> { await Deno.mkdir(path, { recursive: true }); }
function jobTempDir(j: { id: string; settings: Settings }): string { return join(j.settings.download_dir, '.localtube-tmp', j.id); }
async function cleanupJobTemp(j: { id: string; settings: Settings }): Promise<void> {
  const dir = jobTempDir(j); const root = dirname(dir);
  try { await Deno.remove(dir, { recursive: true }); } catch { /* already gone */ }
  try {
    let empty = true;
    for await (const _ of Deno.readDir(root)) { empty = false; break; }
    if (empty) await Deno.remove(root);
  } catch { /* root may not exist or may contain another active job */ }
}""",
1)

old_builder = """async function buildDownloadCommand(spec: { url: string; mode: 'video' | 'audio'; height: 'best' | number; title: string; settings: Settings }): Promise<string[]> {
  const s = spec.settings;
  const args = [
    ...(await commonYtdlpArgs(s)), '--newline', '--progress', '--progress-delta', '0.5',
    '--progress-template', 'download:__LOCALTUBE_PROGRESS__:%(progress._percent_str)s\\t%(progress._speed_str)s\\t%(progress._eta_str)s',
    '--retries', '10', '--fragment-retries', '10', '--file-access-retries', '3', '--retry-sleep', '2',
    '--concurrent-fragments', '4', '--continue', '--part', '--no-overwrites', '--trim-filenames', '180',
    '--paths', s.download_dir, '--print', 'after_move:__LOCALTUBE_FINAL__:%(filepath)s',
  ];"""
new_builder = """async function buildDownloadCommand(spec: { id: string; url: string; mode: 'video' | 'audio'; height: 'best' | number; title: string; settings: Settings }): Promise<string[]> {
  const s = spec.settings;
  const tempDir = jobTempDir(spec);
  const args = [
    ...(await commonYtdlpArgs(s)), '--newline', '--progress', '--progress-delta', '0.5',
    '--progress-template', 'download:__LOCALTUBE_PROGRESS__:%(progress.status)s\\t%(info.format_id)s\\t%(progress.downloaded_bytes)s\\t%(progress.total_bytes)s\\t%(progress.total_bytes_estimate)s\\t%(progress.speed)s\\t%(progress.eta)s\\t%(progress.fragment_index)s\\t%(progress.fragment_count)s\\t%(progress.filename)s',
    '--progress-template', 'postprocess:__LOCALTUBE_POSTPROCESS__:%(progress.status)s',
    '--retries', '10', '--fragment-retries', '10', '--file-access-retries', '3', '--retry-sleep', '2',
    '--concurrent-fragments', '4', '--continue', '--part', '--no-overwrites', '--trim-filenames', '180',
    '--paths', s.download_dir, '--paths', `temp:${tempDir}`, '--print', 'after_move:__LOCALTUBE_FINAL__:%(filepath)s',
  ];"""
if old_builder not in text:
    raise SystemExit('download builder block not found')
text = text.replace(old_builder, new_builder, 1)
text = text.replace(
"    speed: j.speed, eta: j.eta, phase: j.phase, playlist_item: j.playlist_item, outputs: [...j.outputs], error: j.error,",
"    speed: j.speed, eta: j.eta, downloaded_bytes: j.downloaded_bytes, total_bytes: j.total_bytes, total_is_estimate: j.total_is_estimate,\n    final_size_bytes: j.final_size_bytes, current_file: j.current_file, postprocessing: j.postprocessing,\n    phase: j.phase, playlist_item: j.playlist_item, outputs: [...j.outputs], error: j.error,",
1)
text = text.replace(
"          state, percent: Number(item.percent) || 0, speed: safeString(item.speed, 80), eta: safeString(item.eta, 80),\n          phase:",
"          state, percent: Number(item.percent) || 0, speed: safeString(item.speed, 80), eta: safeString(item.eta, 80),\n          downloaded_bytes: Number(item.downloaded_bytes) || 0, total_bytes: Number(item.total_bytes) || 0, total_is_estimate: item.total_is_estimate === true,\n          final_size_bytes: Number(item.final_size_bytes) || 0, current_file: safeString(item.current_file, 4096), postprocessing: false, progress_parts: {},\n          phase:",
1)
text = text.replace(
"      state: 'queued', percent: 0, speed: '', eta: '', phase: 'В очереди', playlist_item: '', outputs: [], error: '',",
"      state: 'queued', percent: 0, speed: '', eta: '', downloaded_bytes: 0, total_bytes: 0, total_is_estimate: false,\n      final_size_bytes: 0, current_file: '', postprocessing: false, progress_parts: {}, phase: 'В очереди', playlist_item: '', outputs: [], error: '',",
1)

start = text.index('  log(j: Job, line: string): void {')
end = text.index('  async readLines(stream: ReadableStream<Uint8Array>, j: Job): Promise<void> {', start)
new_log = r'''  log(j: Job, line: string): void {
    const s = line.trimEnd(); if (!s) return;
    j.logs.push(s.slice(-1400)); if (j.logs.length > MAX_LOG_LINES) j.logs.splice(0, j.logs.length - MAX_LOG_LINES);
    if (s.startsWith('__LOCALTUBE_FINAL__:')) {
      const p = s.slice('__LOCALTUBE_FINAL__:'.length).trim();
      if (p && !j.outputs.includes(p)) j.outputs.push(p);
      j.percent = Math.max(j.percent, 99); j.phase = 'Финализация'; j.postprocessing = true; j.speed = ''; j.eta = '';
      return;
    }
    if (s.startsWith('__LOCALTUBE_PROGRESS__:')) {
      const fields = s.slice('__LOCALTUBE_PROGRESS__:'.length).split('\t');
      const status = (fields[0] || '').trim(); const formatId = (fields[1] || '').trim();
      const downloaded = rawNumber((fields[2] || '').trim()) ?? 0;
      const exactTotal = rawNumber((fields[3] || '').trim()); const estimatedTotal = rawNumber((fields[4] || '').trim());
      const total = exactTotal ?? estimatedTotal ?? 0; const estimated = exactTotal === null && estimatedTotal !== null;
      const speed = rawNumber((fields[5] || '').trim()); const eta = rawNumber((fields[6] || '').trim());
      const fragmentIndex = rawNumber((fields[7] || '').trim()); const fragmentCount = rawNumber((fields[8] || '').trim());
      const filename = fields.slice(9).join('\t').trim();
      const key = `${formatId || 'format'}|${filename || 'current'}`;
      j.progress_parts[key] = { downloaded, total, estimated };
      const parts = Object.values(j.progress_parts);
      j.downloaded_bytes = parts.reduce((n, p) => n + p.downloaded, 0);
      j.total_bytes = parts.reduce((n, p) => n + p.total, 0);
      j.total_is_estimate = parts.some((p) => p.estimated);
      j.current_file = filename;
      j.speed = formatRate(speed); j.eta = formatEtaSeconds(eta); j.postprocessing = false;
      if (j.total_bytes > 0) j.percent = clamp((j.downloaded_bytes / j.total_bytes) * 95, 0, 95);
      else if (fragmentIndex !== null && fragmentCount !== null && fragmentCount > 0) j.percent = clamp((fragmentIndex / fragmentCount) * 95, 0, 95);
      else j.percent = Math.min(j.percent, 94);
      j.phase = status === 'finished' ? 'Поток загружен' : 'Загрузка';
      return;
    }
    if (s.startsWith('__LOCALTUBE_POSTPROCESS__:')) {
      j.postprocessing = true; j.percent = Math.max(j.percent, 96); j.speed = ''; j.eta = ''; j.phase = 'Обработка'; return;
    }
    const pm = s.match(/\[download\]\s+Downloading item\s+(\d+)\s+of\s+(\d+)/);
    if (pm) { j.playlist_item = `${pm[1]}/${pm[2]}`; j.percent = 0; j.progress_parts = {}; j.downloaded_bytes = 0; j.total_bytes = 0; j.phase = 'Загрузка плейлиста'; return; }
    if (/\[Merger\]/.test(s)) { j.phase = 'Слияние видео и аудио'; j.postprocessing = true; j.percent = Math.max(j.percent, 96); j.speed = ''; j.eta = ''; }
    else if (/\[(VideoRemuxer|VideoConvertor)\]/.test(s)) { j.phase = 'Финализация контейнера'; j.postprocessing = true; j.percent = Math.max(j.percent, 97); j.speed = ''; j.eta = ''; }
    else if (/\[ExtractAudio\]/.test(s)) { j.phase = 'Конвертация аудио'; j.postprocessing = true; j.percent = Math.max(j.percent, 96); j.speed = ''; j.eta = ''; }
    else if (/\[Metadata\]/.test(s)) { j.phase = 'Запись метаданных'; j.postprocessing = true; j.percent = Math.max(j.percent, 98); j.speed = ''; j.eta = ''; }
    else if (/\[EmbedThumbnail\]/.test(s)) { j.phase = 'Встраивание обложки'; j.postprocessing = true; j.percent = Math.max(j.percent, 98); j.speed = ''; j.eta = ''; }
    if (s.startsWith('ERROR:')) j.error = s.slice(6).trim().slice(0, 1000);
  }
'''
text = text[:start] + new_log + text[end:]
text = text.replace(
"    j.state = 'running'; j.started_at = nowIso(); j.phase = 'Подготовка'; await this.persist();\n    try {\n      const args = await buildDownloadCommand(j);",
"    j.state = 'running'; j.started_at = nowIso(); j.phase = 'Подготовка'; j.postprocessing = false; await this.persist();\n    try {\n      await ensureDir(jobTempDir(j));\n      const args = await buildDownloadCommand(j);",
1)
text = text.replace(
"      else if (status.success) { j.state = 'completed'; j.percent = 100; j.phase = 'Готово'; }",
"""      else if (status.success) {
        j.state = 'completed'; j.percent = 100; j.phase = 'Готово'; j.postprocessing = false; j.speed = ''; j.eta = '';
        let finalSize = 0;
        for (const output of j.outputs) { try { const st = await Deno.stat(output); if (st.isFile) finalSize += st.size; } catch { /* ignore */ } }
        j.final_size_bytes = finalSize;
      }""",
1)
text = text.replace(
"    finally { j.finished_at = nowIso(); j.process = undefined; await this.persist(); }",
"    finally { j.finished_at = nowIso(); j.process = undefined; await cleanupJobTemp(j); await this.persist(); }",
1)
text = text.replace(
"buildDownloadCommand({ url: TEST_VIDEO_URL, mode: 'video'",
"buildDownloadCommand({ id: 'selftest-video', url: TEST_VIDEO_URL, mode: 'video'",
1)
text = text.replace(
"buildDownloadCommand({ url: TEST_VIDEO_URL, mode: 'audio'",
"buildDownloadCommand({ id: 'selftest-audio', url: TEST_VIDEO_URL, mode: 'audio'",
1)
text = text.replace(
"    const denoRuntimeOk = videoArgs.includes(`deno:${DENO_BIN}`) && videoArgs.includes('ejs:github');",
"    const denoRuntimeOk = videoArgs.includes(`deno:${DENO_BIN}`) && videoArgs.includes('ejs:github');\n    const progressPipelineOk = videoArgs.some((v) => v.includes('progress.downloaded_bytes')) && videoArgs.some((v) => v.includes('postprocess:__LOCALTUBE_POSTPROCESS__')) && videoArgs.some((v) => v.includes('temp:') && v.includes('.localtube-tmp'));",
1)
text = text.replace(
"    const ok = Boolean(status.ready) && staticOk.every(Boolean) && commandOk && mp4CompatibilityOk && denoRuntimeOk && audioOk && urlValidationOk;",
"    const ok = Boolean(status.ready) && staticOk.every(Boolean) && commandOk && mp4CompatibilityOk && denoRuntimeOk && progressPipelineOk && audioOk && urlValidationOk;",
1)
text = text.replace(
"      command_builder: { video_cap: commandOk, mp4_compatibility: mp4CompatibilityOk, deno_ejs_runtime: denoRuntimeOk, audio: audioOk },",
"      command_builder: { video_cap: commandOk, mp4_compatibility: mp4CompatibilityOk, deno_ejs_runtime: denoRuntimeOk, progress_pipeline: progressPipelineOk, audio: audioOk },",
1)
p.write_text(text, encoding='utf-8')

# ---- Web UI: truthful byte progress + indeterminate postprocessing ----
p = Path('app/static/app.js')
text = p.read_text(encoding='utf-8')
old = """      const extra = [j.playlist_item ? `Видео ${j.playlist_item}` : '', j.speed || '', j.eta ? `осталось ${j.eta}` : ''].filter(Boolean).join(' · ');
      card.querySelector('.job-extra').textContent = extra;
      card.querySelector('.progress-bar').style.width = `${j.state === 'completed' ? 100 : pct}%`;
      card.querySelector('.progress-left').textContent = j.state === 'running' ? `${Math.round(pct)}%` : stateText(j);
      card.querySelector('.progress-right').textContent = j.outputs?.length ? basename(j.outputs[j.outputs.length - 1]) : basename(j.download_dir || '');"""
new = """      const sizeText = j.state === 'completed' && j.final_size_bytes
        ? fmtBytes(j.final_size_bytes)
        : j.total_bytes ? `${fmtBytes(j.downloaded_bytes)} / ${j.total_is_estimate ? '≈' : ''}${fmtBytes(j.total_bytes)}`
        : j.downloaded_bytes ? fmtBytes(j.downloaded_bytes) : '';
      const extra = [j.playlist_item ? `Видео ${j.playlist_item}` : '', j.speed || '', j.eta ? `осталось ${j.eta}` : ''].filter(Boolean).join(' · ');
      card.querySelector('.job-extra').textContent = extra;
      card.classList.toggle('postprocessing', j.state === 'running' && !!j.postprocessing);
      card.querySelector('.progress-bar').style.width = `${j.state === 'completed' ? 100 : pct}%`;
      card.querySelector('.progress-left').textContent = j.state === 'running'
        ? (j.postprocessing ? stateText(j) : `${Math.round(pct)}%${sizeText ? ` · ${sizeText}` : ''}`)
        : `${stateText(j)}${sizeText ? ` · ${sizeText}` : ''}`;
      card.querySelector('.progress-right').textContent = j.outputs?.length ? basename(j.outputs[j.outputs.length - 1]) : (j.current_file ? basename(j.current_file) : basename(j.download_dir || ''));"""
if old not in text:
    raise SystemExit('app.js job rendering block not found')
text = text.replace(old, new, 1)
p.write_text(text, encoding='utf-8')

p = Path('app/static/styles.css')
text = p.read_text(encoding='utf-8')
needle = ".progress-bar { height:100%; width:0%; border-radius:inherit; background:linear-gradient(90deg,#ff4a58,#f32436); transition:width .35s ease; }"
replacement = needle + "\n.job.postprocessing .progress-line { position:relative; }\n.job.postprocessing .progress-bar { width:34% !important; transition:none; animation:localtube-processing 1.15s ease-in-out infinite; }\n@keyframes localtube-processing { 0%{transform:translateX(-115%)} 50%{transform:translateX(95%)} 100%{transform:translateX(295%)} }\n@media (prefers-reduced-motion: reduce) { .job.postprocessing .progress-bar { animation:none; width:96% !important; opacity:.72; } }"
if needle not in text: raise SystemExit('progress css needle missing')
text = text.replace(needle, replacement, 1)
p.write_text(text, encoding='utf-8')

replace_once('app/static/index.html', '<label class="toggle-row"><span><strong>Встроить метаданные</strong><small>Название, автор и обложка для аудиофайлов.</small></span>', '<label class="toggle-row"><span><strong>Встроить метаданные</strong><small>Название/автор; для аудио также обложка. Финализация большого файла может занять некоторое время.</small></span>')

# ---- macOS controls: stop now vs disable autostart, START always re-enables ----
replace_once('control/START.command', 'PORT=$(/bin/cat "$BASE/data/port" 2>/dev/null | /usr/bin/tr -cd \'0-9\'); [ -n "$PORT" ] || PORT=8765\n/bin/launchctl kickstart', 'PORT=$(/bin/cat "$BASE/data/port" 2>/dev/null | /usr/bin/tr -cd \'0-9\'); [ -n "$PORT" ] || PORT=8765\n/bin/launchctl enable "$DOMAIN/$LABEL" >/dev/null 2>&1 || true\n/bin/launchctl kickstart')
write('control/STOP.command', '''#!/bin/sh
LABEL='com.localtube.service'; UID_NUM=$(/usr/bin/id -u); DOMAIN="gui/$UID_NUM"
case "${1:-}" in
  --disable)
    /bin/launchctl disable "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
    /bin/launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
    printf '%s\n' 'LocalTube остановлен, автозапуск отключён. START.command снова включит его.'
    ;;
  *)
    /bin/launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
    printf '%s\n' 'LocalTube остановлен до следующего ручного запуска или входа в macOS.'
    ;;
esac
''')

# ---- Windows source/release entrypoint ----
write('INSTALL.ps1', r'''param([switch]$SelfTest)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Invoke-ProductionInstaller([string]$PackageRoot, [switch]$InnerSelfTest) {
    $inner = Join-Path $PackageRoot 'installer\install-windows.ps1'
    if (-not (Test-Path -LiteralPath $inner -PathType Leaf)) { throw "Installer missing: $inner" }
    if ($InnerSelfTest) { & $inner -SelfTest } else { & $inner }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$releasePayload = Join-Path $Root 'payload\app\server.ts'
$releaseInner = Join-Path $Root 'installer\install-windows.ps1'
if ((Test-Path -LiteralPath $releasePayload) -and (Test-Path -LiteralPath $releaseInner)) {
    Invoke-ProductionInstaller $Root -InnerSelfTest:$SelfTest
    exit 0
}

$required = @(
    'app\server.ts','app\VERSION','app\static\index.html','app\static\app.js','app\static\styles.css',
    'app\scripts\runtime_windows.ps1','app\scripts\run_server.ps1','installer\install-windows.ps1',
    'control\windows\START.ps1','control\windows\STOP.ps1','control\windows\DIAGNOSE.ps1','control\windows\UPDATE.ps1','control\windows\UNINSTALL.ps1'
)
foreach ($rel in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $rel) -PathType Leaf)) { throw "Incomplete source checkout: missing $rel" }
}
if ($SelfTest) {
    & (Join-Path $Root 'installer\install-windows.ps1') -SelfTest
    Write-Host 'LocalTube Windows source-checkout layout self-test: OK'
    exit 0
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('localtube-source-install-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot 'payload'),(Join-Path $tempRoot 'installer'),(Join-Path $tempRoot 'control') | Out-Null
    Copy-Item -LiteralPath (Join-Path $Root 'app') -Destination (Join-Path $tempRoot 'payload\app') -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $Root 'installer\install-windows.ps1') -Destination (Join-Path $tempRoot 'installer\install-windows.ps1') -Force
    Copy-Item -LiteralPath (Join-Path $Root 'control\windows\*') -Destination (Join-Path $tempRoot 'control') -Recurse -Force
    Write-Host 'LocalTube: detected git/source checkout; creating temporary production package.'
    Invoke-ProductionInstaller $tempRoot
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
''')
write('INSTALL.cmd', r'''@echo off
setlocal
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" (
  echo ERROR: Windows PowerShell was not found.
  pause
  exit /b 2
)
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL.ps1" %*
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  echo.
  echo LocalTube installation failed with code %RC%.
  pause
)
exit /b %RC%
''')

# Windows inner installer: validate platform and do all network work before stopping old service.
p = Path('installer/install-windows.ps1')
text = p.read_text(encoding='utf-8')
text = text.replace("if ($SelfTest) {\n    Write-Host \"LocalTube Windows installer self-test: OK (PowerShell $($PSVersionTable.PSVersion))\"\n    exit 0\n}\n", """if ($SelfTest) {
    Write-Host "LocalTube Windows installer self-test: OK (PowerShell $($PSVersionTable.PSVersion))"
    exit 0
}
if ($PSVersionTable.PSVersion.Major -lt 5) { throw 'LocalTube requires Windows PowerShell 5.1 or newer.' }
if (-not [Environment]::Is64BitOperatingSystem) { throw 'LocalTube requires 64-bit Windows 10/11.' }
$os = [Environment]::OSVersion.Version
if ($os.Major -lt 10) { throw "LocalTube requires Windows 10/11; detected $os" }
Write-Host 'LocalTube 1.4.4 — Windows installer'
Write-Host '================================='
Write-Host "Windows: $os"
Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
""", 1)
old_stop = r'''$pidFile = Join-Path $Data 'server.pid'
if (Test-Path -LiteralPath $pidFile) {
    $raw = (Get-Content -LiteralPath $pidFile -Raw).Trim()
    $pidNum = 0
    if ([int]::TryParse($raw, [ref]$pidNum) -and $pidNum -gt 0) {
        & "$env:SystemRoot\System32\taskkill.exe" /PID $pidNum /T /F 2>$null | Out-Null
    }
}
Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue

'''
if old_stop not in text: raise SystemExit('windows early stop block missing')
text = text.replace(old_stop, "$PreviousWasRunning = $false\n$pidFile = Join-Path $Data 'server.pid'\n\n", 1)
marker = """    Write-Host '[4/5] replacing application atomically'
    New-Item -ItemType Directory -Force -Path $Backup | Out-Null
"""
stop_late = r'''    Write-Host '[4/5] replacing application atomically'
    # Do not touch an existing installation until the new runtime and backend have passed self-tests.
    if (Test-Path -LiteralPath $pidFile) {
        $raw = (Get-Content -LiteralPath $pidFile -Raw).Trim()
        $pidNum = 0
        if ([int]::TryParse($raw, [ref]$pidNum) -and $pidNum -gt 0) {
            try { Get-Process -Id $pidNum -ErrorAction Stop | Out-Null; $PreviousWasRunning = $true } catch {}
            & "$env:SystemRoot\System32\taskkill.exe" /PID $pidNum /T /F 2>$null | Out-Null
        }
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $Backup | Out-Null
'''
if marker not in text: raise SystemExit('windows replace marker missing')
text = text.replace(marker, stop_late, 1)
text = text.replace("    throw\n} finally {", """    if ($PreviousWasRunning -and (Test-Path -LiteralPath (Join-Path $Control 'START.ps1'))) {
        try { & (Join-Path $Control 'START.ps1') } catch { Write-Warning 'Previous LocalTube files were restored, but automatic restart failed.' }
    }
    throw
} finally {""", 1)
p.write_text(text, encoding='utf-8')

# ---- Release builder/verifier ----
p = Path('scripts/build_release.py')
text = p.read_text(encoding='utf-8')
old = """    common_payload(stage)
    shutil.copy2(ROOT / 'installer/install-windows.ps1', stage / 'INSTALL.ps1')
    shutil.copytree(ROOT / 'control/windows', stage / 'control')
"""
new = """    common_payload(stage)
    shutil.copy2(ROOT / 'INSTALL.ps1', stage / 'INSTALL.ps1')
    shutil.copy2(ROOT / 'INSTALL.cmd', stage / 'INSTALL.cmd')
    (stage / 'installer').mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / 'installer/install-windows.ps1', stage / 'installer/install-windows.ps1')
    shutil.copytree(ROOT / 'control/windows', stage / 'control')
"""
if old not in text: raise SystemExit('build_windows block missing')
text = text.replace(old,new,1)
text = text.replace("1. Распакуйте ZIP в обычную папку.\n2. Правый клик INSTALL.ps1 → Run with PowerShell.\n   Если PowerShell блокирует локальный скрипт:\n     powershell -NoProfile -ExecutionPolicy Bypass -File ./INSTALL.ps1\n3. После установки используйте LocalTube из меню Пуск.", "1. Распакуйте ZIP в обычную папку.\n2. Дважды щёлкните INSTALL.cmd (рекомендуется).\n   Альтернатива: powershell -NoProfile -ExecutionPolicy Bypass -File .\\INSTALL.ps1\n3. После установки используйте LocalTube из меню Пуск.", 1)
p.write_text(text,encoding='utf-8')

p=Path('scripts/verify_release.py'); text=p.read_text(encoding='utf-8')
text=text.replace("        prefix + 'INSTALL.ps1',\n        prefix + 'MANIFEST.sha256',", "        prefix + 'INSTALL.ps1',\n        prefix + 'INSTALL.cmd',\n        prefix + 'installer/install-windows.ps1',\n        prefix + 'MANIFEST.sha256',",1)
p.write_text(text,encoding='utf-8')

# ---- Tests ----
write('scripts/check_progress_pipeline.py', '''#!/usr/bin/env python3
from pathlib import Path
server=Path('app/server.ts').read_text(encoding='utf-8')
ui=Path('app/static/app.js').read_text(encoding='utf-8')
css=Path('app/static/styles.css').read_text(encoding='utf-8')
build=Path('scripts/build_release.py').read_text(encoding='utf-8')
verify=Path('scripts/verify_release.py').read_text(encoding='utf-8')
errors=[]
for needle in ['progress.downloaded_bytes','progress.total_bytes_estimate','postprocess:__LOCALTUBE_POSTPROCESS__','.localtube-tmp','final_size_bytes','await cleanupJobTemp(j)']:
    if needle not in server: errors.append(f'server missing {needle}')
if 'progress._percent_str' in server: errors.append('server still parses decorative _percent_str')
for needle in ['j.total_bytes','j.final_size_bytes','postprocessing']:
    if needle not in ui: errors.append(f'UI missing {needle}')
if '.job.postprocessing .progress-bar' not in css: errors.append('indeterminate postprocess CSS missing')
for needle in ["ROOT / 'INSTALL.ps1'", "ROOT / 'INSTALL.cmd'", "installer/install-windows.ps1"]:
    if needle not in build: errors.append(f'Windows package builder missing {needle}')
if "prefix + 'INSTALL.cmd'" not in verify: errors.append('Windows verifier does not require INSTALL.cmd')
if errors: raise SystemExit('\n'.join(errors))
print('download progress/temp-file + Windows installer guard: OK')
''')

p=Path('scripts/test.sh'); text=p.read_text(encoding='utf-8')
needle="echo '[loopback] curlrc/proxy isolation regression'\npython3 scripts/check_loopback_transport.py\n"
if needle not in text: raise SystemExit('test.sh insertion point missing')
text=text.replace(needle, needle+"echo '[downloads] progress/temp-file/Windows installer regression'\npython3 scripts/check_progress_pipeline.py\n",1)
p.write_text(text,encoding='utf-8')

# CI Windows parses and self-tests the source entrypoint too.
p=Path('.github/workflows/ci.yml'); text=p.read_text(encoding='utf-8')
text=text.replace("          $files = @(\n            'installer/install-windows.ps1',", "          $files = @(\n            'INSTALL.ps1',\n            'installer/install-windows.ps1',",1)
text=text.replace("          .\\scripts\\ci_windows_integration.ps1", "          .\\INSTALL.ps1 -SelfTest\n          .\\scripts\\ci_windows_integration.ps1",1)
p.write_text(text,encoding='utf-8')

# ---- README / changelog ----
p=Path('README.md'); text=p.read_text(encoding='utf-8')
old_win='''### 🪟 Windows\n\n1. Скачайте `LocalTube-Windows-...zip` и распакуйте.\n2. Запустите **`INSTALL.ps1`** через PowerShell.\n3. Если политика Windows блокирует локальный скрипт, из каталога пакета выполните:\n   ```powershell\n   powershell -NoProfile -ExecutionPolicy Bypass -File .\\INSTALL.ps1\n   ```\n4. После установки запускайте **LocalTube** из меню «Пуск».\n\nПриложение устанавливается без прав администратора в `%LOCALAPPDATA%\\LocalTube`. Runtime и настройки не пишутся в `Program Files` и не требуют системной установки Python/Node.js.\n'''
new_win='''### 🪟 Windows\n\n**Что требуется:** Windows 10/11 x64 или ARM64, штатный Windows PowerShell 5.1+ и интернет на первой установке. **Не нужно заранее ставить Python, Node.js, Deno, yt-dlp, FFmpeg, Chocolatey, winget или права администратора** — LocalTube скачивает и проверяет приватный runtime сам. Если корпоративная сеть полностью блокирует GitHub/CDN, допустим fallback на уже установленные `deno`, `yt-dlp`, `ffmpeg` и `ffprobe` из `PATH`.\n\nГотовый Release:\n\n1. Скачайте `LocalTube-Windows-...zip` и **полностью распакуйте** его. Не запускайте installer прямо из окна ZIP.\n2. Дважды щёлкните **`INSTALL.cmd`** — это рекомендуемый вход: он запускает штатный Windows PowerShell с `-NoProfile -ExecutionPolicy Bypass`.\n3. Альтернатива из PowerShell:\n   ```powershell\n   powershell -NoProfile -ExecutionPolicy Bypass -File .\\INSTALL.ps1\n   ```\n4. После установки запускайте **LocalTube** из меню «Пуск».\n\nУстановка выполняется в `%LOCALAPPDATA%\\LocalTube`, без `Program Files` и без изменения системных runtime. В `%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs` создаётся ярлык LocalTube.\n\nУстановка прямо из `git clone` также поддерживается. Из корня репозитория:\n\n```powershell\n.\\INSTALL.cmd\n# или\npowershell -NoProfile -ExecutionPolicy Bypass -File .\\INSTALL.ps1\n```\n\nSource entrypoint сам создаёт временный production-layout из `app/`, `control/windows/` и `installer/`; Python/Go/Node для установки из исходников не требуются. Только проверка layout без изменений системы: `powershell -NoProfile -ExecutionPolicy Bypass -File .\\INSTALL.ps1 -SelfTest`.\n'''
if old_win not in text: raise SystemExit('README Windows section missing')
text=text.replace(old_win,new_win,1)
insert='''\n### Остановка LocalTube на macOS\n\nОстановить сервис **сейчас**, не удаляя программу:\n\n```bash\n"$HOME/Applications/LocalTube Tools/STOP.command"\n```\n\nИли напрямую через launchd:\n\n```bash\nlaunchctl bootout "gui/$(id -u)/com.localtube.service"\n```\n\nЧтобы одновременно отключить автозапуск при следующем входе в macOS:\n\n```bash\n"$HOME/Applications/LocalTube Tools/STOP.command" --disable\n```\n\nПовторный `START.command` автоматически снова включает LaunchAgent:\n\n```bash\n"$HOME/Applications/LocalTube Tools/START.command"\n```\n'''
anchor='''Source install намеренно доверяет содержимому текущего Git checkout; `MANIFEST.sha256` относится к собранным release-архивам. Скачиваемые Deno/yt-dlp/FFmpeg при этом проверяются теми же upstream SHA-256, что и при обычной release-установке.\n'''
if anchor not in text: raise SystemExit('README mac anchor missing')
text=text.replace(anchor,anchor+insert,1)
# Explain progress semantics and hidden temp files.
needle='''- 📚 плейлисты, очередь, прогресс, скорость, ETA, отмена и история;\n'''
text=text.replace(needle, needle+'''- 📊 прогресс считается по реальным байтам; оценочный размер помечается `≈`, а post-processing показывается отдельной фазой;\n- 🧹 `.part`, отдельные дорожки и FFmpeg `.temp.*` хранятся в скрытом `.localtube-tmp` и удаляются после задачи;\n''',1)
p.write_text(text,encoding='utf-8')

p=Path('CHANGELOG.md'); text=p.read_text(encoding='utf-8')
entry='''## 1.4.4 — 2026-08-16\n\n- исправлен ложный `100%` во время FFmpeg merge/remux/metadata: 100% выставляется только после успешного завершения всей задачи;\n- прогресс теперь использует сырые `downloaded_bytes`, `total_bytes/total_bytes_estimate`, speed и ETA вместо декоративных `_..._str`;\n- несколько video/audio-потоков агрегируются по байтам, оценочный total помечается отдельно;\n- добавлен отдельный postprocess progress channel и indeterminate UI для слияния, конвертации и записи метаданных;\n- промежуточные `.part`, format streams и `.temp.*` перенесены в скрытый `.localtube-tmp/<job>` и автоматически очищаются;\n- после завершения LocalTube показывает фактический размер финального файла;\n- Windows получил `INSTALL.cmd` и единый `INSTALL.ps1`, работающий и из Release, и непосредственно из source checkout без Python/Node/admin;\n- Windows installer больше не останавливает текущую установку до успешного preflight нового runtime/backend;\n- README дополнен полными требованиями Windows и командами остановки/отключения автозапуска macOS.\n\n'''
if '# 🗒️ Changelog\n\n' not in text: raise SystemExit('changelog header missing')
text=text.replace('# 🗒️ Changelog\n\n','# 🗒️ Changelog\n\n'+entry,1)
p.write_text(text,encoding='utf-8')

print('LocalTube 1.4.4 patch prepared')
