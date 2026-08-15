param([switch]$SelfTest)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($SelfTest) {
    Write-Host "LocalTube Windows installer self-test: OK (PowerShell $($PSVersionTable.PSVersion))"
    exit 0
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (Test-Path -LiteralPath (Join-Path $ScriptDir 'payload\app')) { $PackageRoot = $ScriptDir } else { $PackageRoot = Split-Path -Parent $ScriptDir }
$Payload = Join-Path $PackageRoot 'payload\app'
if (-not (Test-Path -LiteralPath (Join-Path $Payload 'server.ts'))) { throw "Payload not found: $Payload" }

$Local = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME 'AppData\Local' }
$Base = Join-Path $Local 'LocalTube'
$App = Join-Path $Base 'app'
$Runtime = Join-Path $Base 'runtime'
$Data = Join-Path $Base 'data'
$Logs = Join-Path $Base 'logs'
$Control = Join-Path $Base 'control'
$Stage = Join-Path $Base ('.install-stage-' + [Guid]::NewGuid().ToString('N'))
$Backup = Join-Path $Base ('.rollback-' + [Guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Force -Path $Base,$Data,$Logs,$Control,$Stage | Out-Null

$pidFile = Join-Path $Data 'server.pid'
if (Test-Path -LiteralPath $pidFile) {
    $raw = (Get-Content -LiteralPath $pidFile -Raw).Trim()
    $pidNum = 0
    if ([int]::TryParse($raw, [ref]$pidNum) -and $pidNum -gt 0) {
        & "$env:SystemRoot\System32\taskkill.exe" /PID $pidNum /T /F 2>$null | Out-Null
    }
}
Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue

try {
    Write-Host '[1/5] staging application'
    $stageApp = Join-Path $Stage 'app'
    New-Item -ItemType Directory -Force -Path $stageApp | Out-Null
    Get-ChildItem -LiteralPath $Payload | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $stageApp -Recurse -Force }

    Write-Host '[2/5] installing verified runtime'
    . (Join-Path $stageApp 'scripts\runtime_windows.ps1')
    $stageRuntime = Join-Path $Stage 'runtime'
    Install-LocalTubeRuntime $stageRuntime

    Write-Host '[3/5] validating backend'
    $env:LOCALTUBE_BASE = $Stage
    $env:LOCALTUBE_APP_DIR = $stageApp
    $env:LOCALTUBE_RUNTIME_DIR = $stageRuntime
    & (Join-Path $stageRuntime 'deno.exe') run --no-config -A (Join-Path $stageApp 'server.ts') --self-test | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Backend self-test failed' }

    Write-Host '[4/5] replacing application atomically'
    New-Item -ItemType Directory -Force -Path $Backup | Out-Null
    if (Test-Path -LiteralPath $App) { Move-Item -LiteralPath $App -Destination (Join-Path $Backup 'app') }
    if (Test-Path -LiteralPath $Runtime) { Move-Item -LiteralPath $Runtime -Destination (Join-Path $Backup 'runtime') }
    Move-Item -LiteralPath $stageApp -Destination $App
    Move-Item -LiteralPath $stageRuntime -Destination $Runtime
    if (-not (Test-Path -LiteralPath (Join-Path $Data 'port'))) { Set-Content -LiteralPath (Join-Path $Data 'port') -Value '8765' -Encoding ASCII }

    Write-Host '[5/5] installing controls and Start Menu shortcut'
    New-Item -ItemType Directory -Force -Path $Control | Out-Null
    $sourceControl = Join-Path $PackageRoot 'control\windows'
    Get-ChildItem -LiteralPath $sourceControl | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $Control -Recurse -Force }

    $Programs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $Shortcut = Join-Path $Programs 'LocalTube.lnk'
    $Shell = New-Object -ComObject WScript.Shell
    $Link = $Shell.CreateShortcut($Shortcut)
    $Link.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $Link.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$Control\START.ps1`""
    $Link.WorkingDirectory = $Base
    $Link.Save()

    & "$Control\START.ps1"
    Write-Host "LocalTube installed in $Base"
    Remove-Item -LiteralPath $Backup -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    if (Test-Path -LiteralPath $Backup) {
        Remove-Item -LiteralPath $App -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $Runtime -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath (Join-Path $Backup 'app')) { Move-Item -LiteralPath (Join-Path $Backup 'app') -Destination $App }
        if (Test-Path -LiteralPath (Join-Path $Backup 'runtime')) { Move-Item -LiteralPath (Join-Path $Backup 'runtime') -Destination $Runtime }
    }
    throw
} finally {
    Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
}
