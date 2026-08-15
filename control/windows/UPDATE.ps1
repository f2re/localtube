Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$Base=Join-Path $env:LOCALAPPDATA 'LocalTube'; $App=Join-Path $Base 'app'; $Runtime=Join-Path $Base 'runtime'
if(Test-Path (Join-Path $Base 'control\STOP.ps1')){ & (Join-Path $Base 'control\STOP.ps1') }
. (Join-Path $App 'scripts\runtime_windows.ps1')
Install-LocalTubeRuntime $Runtime
& (Join-Path $Base 'control\START.ps1')
