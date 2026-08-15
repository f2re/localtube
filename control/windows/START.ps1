Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Base = Join-Path $env:LOCALAPPDATA 'LocalTube'
$Data = Join-Path $Base 'data'
$Logs = Join-Path $Base 'logs'
$Runner = Join-Path $Base 'app\scripts\run_server.ps1'
$Port = 8765

$portFile = Join-Path $Data 'port'
if (Test-Path -LiteralPath $portFile) {
    $raw = (Get-Content -LiteralPath $portFile -Raw).Trim()
    $n = 0
    if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1024 -and $n -le 65535) { $Port = $n }
}

function Test-LocalTubeHealth {
    try {
        $tokenFile = Join-Path $Data 'api_token'
        if (-not (Test-Path -LiteralPath $tokenFile)) { return $false }
        $token = (Get-Content -LiteralPath $tokenFile -Raw).Trim()
        if ($token.Length -lt 32) { return $false }
        $health = Invoke-RestMethod -UseBasicParsing -TimeoutSec 2 -Headers @{'X-LocalTube-Token'=$token} -Uri "http://127.0.0.1:$Port/api/health"
        return [bool]($health.ok -and $health.runtime.ready)
    } catch {
        return $false
    }
}

if (-not (Test-LocalTubeHealth)) {
    New-Item -ItemType Directory -Force -Path $Logs | Out-Null
    if (-not (Test-Path -LiteralPath $Runner)) { throw "LocalTube launcher missing: $Runner" }
    $powershell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$Runner`""
    Start-Process -WindowStyle Hidden -FilePath $powershell -ArgumentList $arguments | Out-Null
    for ($i = 0; $i -lt 30 -and -not (Test-LocalTubeHealth); $i++) { Start-Sleep -Seconds 1 }
}

if (-not (Test-LocalTubeHealth)) { throw "LocalTube did not start. Logs: $Logs" }
Start-Process "http://127.0.0.1:$Port/"
