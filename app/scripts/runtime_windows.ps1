Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-LTArch {
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { return 'arm64' }
    if ([Environment]::Is64BitOperatingSystem) { return 'amd64' }
    throw 'LocalTube requires 64-bit Windows (x64 or ARM64).'
}

function Invoke-LTDownload([string]$Uri, [string]$OutFile, [string]$Label) {
    Write-Host "  -> $Label"
    Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $OutFile
}

function Get-LTNamedHash([string]$ChecksumFile, [string]$Asset) {
    foreach ($line in Get-Content -LiteralPath $ChecksumFile) {
        if ($line -match '^\s*([0-9A-Fa-f]{64})\s+\*?(.+?)\s*$' -and $Matches[2] -eq $Asset) {
            return $Matches[1].ToLowerInvariant()
        }
    }
    return $null
}

function Assert-LTNamedHash([string]$File, [string]$ChecksumFile, [string]$Asset) {
    $expected = Get-LTNamedHash $ChecksumFile $Asset
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $File).Hash.ToLowerInvariant()
    if (-not $expected -or $expected -ne $actual) { throw "SHA-256 mismatch for $Asset" }
    Write-Host '     SHA-256 OK'
}

function Assert-LTSingleHash([string]$File, [string]$ChecksumFile) {
    $text = Get-Content -LiteralPath $ChecksumFile -Raw
    if ($text -notmatch '([0-9A-Fa-f]{64})') { throw "No SHA-256 in $ChecksumFile" }
    $expected = $Matches[1].ToLowerInvariant()
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $File).Hash.ToLowerInvariant()
    if ($expected -ne $actual) { throw "SHA-256 mismatch for $(Split-Path -Leaf $File)" }
    Write-Host '     SHA-256 OK'
}

function Copy-LTZipBinary([string]$Zip, [string]$Name, [string]$Destination, [string]$TempRoot) {
    $extract = Join-Path $TempRoot ([Guid]::NewGuid().ToString('N'))
    Expand-Archive -LiteralPath $Zip -DestinationPath $extract -Force
    $found = Get-ChildItem -LiteralPath $extract -Recurse -File | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (-not $found) { throw "$Name not found in archive" }
    Copy-Item -LiteralPath $found.FullName -Destination $Destination -Force
}

function Test-LTDeno([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $line = (& $Path --version 2>$null | Select-Object -First 1)
        return [bool]($line -match '^deno\s+([0-9]+)\.([0-9]+)' -and ([int]$Matches[1] -gt 2 -or ([int]$Matches[1] -eq 2 -and [int]$Matches[2] -ge 3)))
    } catch { return $false }
}

function Copy-LTExternal([string]$Name, [string]$Destination) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) { return $false }
    Copy-Item -LiteralPath $cmd.Source -Destination $Destination -Force
    return $true
}

function Install-LocalTubeRuntime([string]$RuntimeDir) {
    $arch = Get-LTArch
    $temp = Join-Path ([IO.Path]::GetTempPath()) ("localtube-" + [Guid]::NewGuid().ToString('N'))
    $stage = Join-Path $temp 'runtime'
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    try {
        Write-Host '[runtime 1/4] Deno >= 2.3'
        $denoAsset = if ($arch -eq 'arm64') { 'deno-aarch64-pc-windows-msvc.zip' } else { 'deno-x86_64-pc-windows-msvc.zip' }
        $denoZip = Join-Path $temp $denoAsset
        $denoSum = "$denoZip.sha256sum"
        try {
            Invoke-LTDownload "https://github.com/denoland/deno/releases/latest/download/$denoAsset" $denoZip 'downloading official Deno'
            Invoke-LTDownload "https://github.com/denoland/deno/releases/latest/download/$denoAsset.sha256sum" $denoSum 'downloading Deno checksum'
            Assert-LTSingleHash $denoZip $denoSum
            Copy-LTZipBinary $denoZip 'deno.exe' (Join-Path $stage 'deno.exe') $temp
            if (-not (Test-LTDeno (Join-Path $stage 'deno.exe'))) { throw 'Deno self-check failed' }
            $denoSource = 'github.com/denoland/deno release + SHA-256'
        } catch {
            if (-not (Copy-LTExternal 'deno.exe' (Join-Path $stage 'deno.exe'))) { throw }
            if (-not (Test-LTDeno (Join-Path $stage 'deno.exe'))) { throw 'Existing Deno is older than 2.3.0' }
            $denoSource = 'external PATH'
        }

        Write-Host '[runtime 2/4] yt-dlp'
        $ytAsset = if ($arch -eq 'arm64') { 'yt-dlp_arm64.exe' } else { 'yt-dlp.exe' }
        $ytDest = Join-Path $stage 'yt-dlp.exe'
        $ytOk = $false
        foreach ($base in @(
            'https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download',
            'https://github.com/yt-dlp/yt-dlp/releases/latest/download'
        )) {
            try {
                $ytFile = Join-Path $temp $ytAsset
                $ytSums = Join-Path $temp 'SHA2-256SUMS'
                Invoke-LTDownload "$base/$ytAsset" $ytFile "downloading yt-dlp ($ytAsset)"
                Invoke-LTDownload "$base/SHA2-256SUMS" $ytSums 'downloading yt-dlp checksums'
                Assert-LTNamedHash $ytFile $ytSums $ytAsset
                Copy-Item -LiteralPath $ytFile -Destination $ytDest -Force
                & $ytDest --version | Out-Null
                if ($LASTEXITCODE -ne 0) { throw 'yt-dlp self-check failed' }
                $ytSource = "$base + SHA-256"
                $ytOk = $true; break
            } catch { $ytOk = $false }
        }
        if (-not $ytOk) {
            if (-not (Copy-LTExternal 'yt-dlp.exe' $ytDest)) { throw 'Unable to install yt-dlp' }
            $ytSource = 'external PATH'
        }

        Write-Host '[runtime 3/4] FFmpeg + FFprobe'
        $ffAsset = if ($arch -eq 'arm64') { 'ffmpeg-master-latest-winarm64-gpl.zip' } else { 'ffmpeg-master-latest-win64-gpl.zip' }
        $ffZip = Join-Path $temp $ffAsset
        $ffSums = Join-Path $temp 'checksums.sha256'
        $ffOk = $false
        try {
            $ffBase = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest'
            Invoke-LTDownload "$ffBase/$ffAsset" $ffZip 'downloading FFmpeg build'
            Invoke-LTDownload "$ffBase/checksums.sha256" $ffSums 'downloading FFmpeg checksums'
            Assert-LTNamedHash $ffZip $ffSums $ffAsset
            Copy-LTZipBinary $ffZip 'ffmpeg.exe' (Join-Path $stage 'ffmpeg.exe') $temp
            Copy-LTZipBinary $ffZip 'ffprobe.exe' (Join-Path $stage 'ffprobe.exe') $temp
            & (Join-Path $stage 'ffmpeg.exe') -version | Out-Null
            & (Join-Path $stage 'ffprobe.exe') -version | Out-Null
            $ffSource = 'github.com/BtbN/FFmpeg-Builds latest + SHA-256'; $ffOk = $true
        } catch { $ffOk = $false }
        if (-not $ffOk) {
            if (-not (Copy-LTExternal 'ffmpeg.exe' (Join-Path $stage 'ffmpeg.exe'))) { throw 'Unable to install FFmpeg' }
            if (-not (Copy-LTExternal 'ffprobe.exe' (Join-Path $stage 'ffprobe.exe'))) { throw 'Unable to install FFprobe' }
            $ffSource = 'external PATH'
        }

        Write-Host '[runtime 4/4] executable self-tests'
        & (Join-Path $stage 'deno.exe') --version | Out-Null
        & (Join-Path $stage 'yt-dlp.exe') --version | Out-Null
        & (Join-Path $stage 'ffmpeg.exe') -version | Out-Null
        & (Join-Path $stage 'ffprobe.exe') -version | Out-Null

        $manifest = [ordered]@{
            installed_at=(Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); platform='windows'; architecture=$arch;
            deno=(& (Join-Path $stage 'deno.exe') --version | Select-Object -First 1); deno_source=$denoSource;
            yt_dlp=(& (Join-Path $stage 'yt-dlp.exe') --version | Select-Object -First 1); yt_dlp_source=$ytSource;
            ffmpeg=(& (Join-Path $stage 'ffmpeg.exe') -version | Select-Object -First 1); ffmpeg_source=$ffSource
        }
        $manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stage 'manifest.json') -Encoding UTF8

        Remove-Item -LiteralPath $RuntimeDir -Recurse -Force -ErrorAction SilentlyContinue
        Move-Item -LiteralPath $stage -Destination $RuntimeDir
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
