param([switch]$SelfTest)
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
    New-Item -ItemType Directory -Force -Path (Join-Path $tempRoot 'payload'),(Join-Path $tempRoot 'installer'),(Join-Path $tempRoot 'control\windows') | Out-Null
    Copy-Item -LiteralPath (Join-Path $Root 'app') -Destination (Join-Path $tempRoot 'payload\app') -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $Root 'installer\install-windows.ps1') -Destination (Join-Path $tempRoot 'installer\install-windows.ps1') -Force
    Get-ChildItem -LiteralPath (Join-Path $Root 'control\windows') | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $tempRoot 'control\windows') -Recurse -Force }
    Write-Host 'LocalTube: detected git/source checkout; creating temporary production package.'
    Invoke-ProductionInstaller $tempRoot
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
