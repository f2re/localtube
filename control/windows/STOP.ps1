$ErrorActionPreference='SilentlyContinue'
$Data=Join-Path (Join-Path $env:LOCALAPPDATA 'LocalTube') 'data'
$pidFile=Join-Path $Data 'server.pid'
if(Test-Path $pidFile){ $n=0; $raw=(Get-Content $pidFile -Raw).Trim(); if([int]::TryParse($raw,[ref]$n)){ & "$env:SystemRoot\System32\taskkill.exe" /PID $n /T /F | Out-Null }; Remove-Item $pidFile -Force }
