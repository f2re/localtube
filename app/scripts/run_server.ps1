param([string]$Base = $env:LOCALTUBE_BASE)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if (-not $Base) {
    $local = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME 'AppData\Local' }
    $Base = Join-Path $local 'LocalTube'
}
$Runtime = Join-Path $Base 'runtime'
$App = Join-Path $Base 'app'
$Data = Join-Path $Base 'data'
$Logs = Join-Path $Base 'logs'
$Cache = Join-Path $Base 'cache\deno'
New-Item -ItemType Directory -Force -Path $Data,$Logs,$Cache | Out-Null

$Port = 8765
$portFile = Join-Path $Data 'port'
if (Test-Path -LiteralPath $portFile) {
    $raw = (Get-Content -LiteralPath $portFile -Raw).Trim()
    $n = 0
    if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1024 -and $n -le 65535) { $Port = $n }
}

$Deno = Join-Path $Runtime 'deno.exe'
$Ytdlp = Join-Path $Runtime 'yt-dlp.exe'
$Ffmpeg = Join-Path $Runtime 'ffmpeg.exe'
$Ffprobe = Join-Path $Runtime 'ffprobe.exe'
foreach ($f in @($Deno,$Ytdlp,$Ffmpeg,$Ffprobe,(Join-Path $App 'server.ts'))) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "LocalTube runtime/app missing: $f" }
}

$env:LOCALTUBE_BASE = $Base
$env:LOCALTUBE_PORT = [string]$Port
$env:LOCALTUBE_APP_DIR = $App
$env:LOCALTUBE_RUNTIME_DIR = $Runtime
$env:DENO_DIR = $Cache
$env:PATH = "$Runtime;$env:SystemRoot\System32;$env:SystemRoot\System32\WindowsPowerShell\v1.0"
$env:TMPDIR = if ($env:TEMP) { $env:TEMP } else { [IO.Path]::GetTempPath() }
Set-Content -LiteralPath (Join-Path $Data 'server.pid') -Value $PID -Encoding ASCII

$PowerShellExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$ExplorerExe = "$env:SystemRoot\explorer.exe"
$TaskkillExe = "$env:SystemRoot\System32\taskkill.exe"
$allowRun = @($Ytdlp,$Ffmpeg,$Ffprobe,$PowerShellExe,$ExplorerExe,$TaskkillExe) -join ','
$allowEnv = 'HOME,USERPROFILE,LOCALAPPDATA,APPDATA,USERNAME,PATH,TEMP,TMP,TMPDIR,SystemRoot,LOCALTUBE_BASE,LOCALTUBE_PORT,LOCALTUBE_APP_DIR,LOCALTUBE_RUNTIME_DIR,DENO_DIR'
$args = @(
    'run','--no-config','--no-prompt',
    '--allow-read','--allow-write',
    "--allow-run=$allowRun",
    "--allow-env=$allowEnv",
    "--allow-net=127.0.0.1:$Port,localhost:$Port",
    (Join-Path $App 'server.ts')
)

try {
    & $Deno @args
    exit $LASTEXITCODE
} finally {
    Remove-Item -LiteralPath (Join-Path $Data 'server.pid') -Force -ErrorAction SilentlyContinue
}
