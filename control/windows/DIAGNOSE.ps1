Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$Base=Join-Path $env:LOCALAPPDATA 'LocalTube'; $Data=Join-Path $Base 'data'
$Port=8765; if(Test-Path (Join-Path $Data 'port')){$n=0;$raw=(Get-Content (Join-Path $Data 'port') -Raw).Trim();if([int]::TryParse($raw,[ref]$n)){$Port=$n}}
$token=(Get-Content (Join-Path $Data 'api_token') -Raw).Trim()
Invoke-RestMethod -UseBasicParsing -Headers @{'Content-Type'='application/json';'X-LocalTube-Token'=$token} -Method Post -Body '{}' -Uri "http://127.0.0.1:$Port/api/diagnostics" | ConvertTo-Json -Depth 8
