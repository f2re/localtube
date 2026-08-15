$ErrorActionPreference='SilentlyContinue'
$Base=Join-Path $env:LOCALAPPDATA 'LocalTube'; $Control=Join-Path $Base 'control'
if(Test-Path (Join-Path $Control 'STOP.ps1')){ & (Join-Path $Control 'STOP.ps1') }
Remove-Item (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\LocalTube.lnk') -Force
Remove-Item $Base -Recurse -Force
Write-Host 'LocalTube uninstalled.'
