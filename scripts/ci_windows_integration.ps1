Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Work = Join-Path ([IO.Path]::GetTempPath()) ('localtube-ci-' + [Guid]::NewGuid().ToString('N'))
$Base = Join-Path $Work 'LocalTube'
$App = Join-Path $Base 'app'; $Runtime = Join-Path $Base 'runtime'; $Data = Join-Path $Base 'data'; $Logs = Join-Path $Base 'logs'
New-Item -ItemType Directory -Force -Path $App,$Data,$Logs | Out-Null
Get-ChildItem -LiteralPath (Join-Path $Root 'app') | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $App -Recurse -Force }
try {
    Write-Host '[windows 1/4] install verified runtime'
    . (Join-Path $App 'scripts\runtime_windows.ps1')
    Install-LocalTubeRuntime $Runtime

    Write-Host '[windows 2/4] backend self-test'
    $env:LOCALTUBE_BASE=$Base; $env:LOCALTUBE_APP_DIR=$App; $env:LOCALTUBE_RUNTIME_DIR=$Runtime
    & (Join-Path $Runtime 'deno.exe') run --no-config -A (Join-Path $App 'server.ts') --self-test
    if ($LASTEXITCODE -ne 0) { throw 'backend self-test failed' }

    Write-Host '[windows 3/4] restricted server start'
    Set-Content -LiteralPath (Join-Path $Data 'port') -Value '18767' -Encoding ASCII
    $runner = Join-Path $App 'scripts\run_server.ps1'
    $proc = Start-Process -PassThru -WindowStyle Hidden -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$runner`"")
    try {
        $token = ''
        for ($i=0; $i -lt 40; $i++) {
            $tf = Join-Path $Data 'api_token'
            if (Test-Path $tf) { $token = (Get-Content $tf -Raw).Trim() }
            if ($token) {
                try {
                    $health = Invoke-RestMethod -UseBasicParsing -TimeoutSec 3 -Headers @{'X-LocalTube-Token'=$token} -Uri 'http://127.0.0.1:18767/api/health'
                    if ($health.ok -and $health.runtime.ready) { break }
                } catch {}
            }
            Start-Sleep -Seconds 1
        }
        if (-not $token) { throw 'API token not created' }
        $health = Invoke-RestMethod -UseBasicParsing -Headers @{'X-LocalTube-Token'=$token} -Uri 'http://127.0.0.1:18767/api/health'
        if (-not $health.ok -or -not $health.runtime.ready -or $health.runtime.platform -ne 'windows') { throw 'health check failed' }
        Write-Host '[windows 4/4] health OK'
    } finally {
        & "$env:SystemRoot\System32\taskkill.exe" /PID $proc.Id /T /F 2>$null | Out-Null
    }
    Write-Host 'Windows integration: OK'
} finally {
    Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
}
