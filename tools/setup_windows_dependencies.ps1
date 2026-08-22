$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Get-VerifiedArchive([string]$Url, [string]$ExpectedSha256, [string]$Destination) {
    Write-Host "Downloading: $Url"
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Destination
    $Actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Destination).Hash.ToLowerInvariant()
    if ($Actual -ne $ExpectedSha256.ToLowerInvariant()) {
        throw "SHA-256 mismatch for $Url`nExpected: $ExpectedSha256`nActual:   $Actual"
    }
    Write-Host "SHA-256 OK: $Actual"
}

function Replace-Directory([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Required extracted directory is missing: $Source"
    }
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

$Temp = Join-Path ([System.IO.Path]::GetTempPath()) ("notlight-deps-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $Temp | Out-Null

try {
    # EIRTeam.FFmpeg v1.1.4. The project keeps its trimmed ffmpeg.gdextension;
    # only the verified runtime directories are restored.
    $EirUrl = "https://github.com/EIRTeam/EIRTeam.FFmpeg/releases/download/autobuild-2025-11-12-13-44/eirteam-ffmpeg-1.1.4.zip"
    $EirSha = "1a8dbc4d7524172ca72517dac4ffb24965025c2f19067882be35376b75bc107c"
    $EirZip = Join-Path $Temp "eirteam-ffmpeg-1.1.4.zip"
    $EirExtract = Join-Path $Temp "eirteam"
    Get-VerifiedArchive $EirUrl $EirSha $EirZip
    Expand-Archive -LiteralPath $EirZip -DestinationPath $EirExtract -Force
    Replace-Directory (Join-Path $EirExtract "addons\ffmpeg\win64") (Join-Path $Root "addons\ffmpeg\win64")
    Replace-Directory (Join-Path $EirExtract "addons\ffmpeg\linux64") (Join-Path $Root "addons\ffmpeg\linux64")
    Write-Host "EIRTeam.FFmpeg v1.1.4 runtime restored."

    # Gyan.dev FFmpeg 8.1.2 Essentials CLI.
    $FfmpegUrl = "https://www.gyan.dev/ffmpeg/builds/packages/ffmpeg-8.1.2-essentials_build.zip"
    $FfmpegSha = "db580001caa24ac104c8cb856cd113a87b0a443f7bdf47d8c12b1d740584a2ec"
    $FfmpegZip = Join-Path $Temp "ffmpeg-8.1.2-essentials_build.zip"
    $FfmpegExtract = Join-Path $Temp "ffmpeg-cli"
    Get-VerifiedArchive $FfmpegUrl $FfmpegSha $FfmpegZip
    Expand-Archive -LiteralPath $FfmpegZip -DestinationPath $FfmpegExtract -Force
    $FfmpegExe = Get-ChildItem -LiteralPath $FfmpegExtract -Filter "ffmpeg.exe" -File -Recurse | Select-Object -First 1
    $FfprobeExe = Get-ChildItem -LiteralPath $FfmpegExtract -Filter "ffprobe.exe" -File -Recurse | Select-Object -First 1
    if ($null -eq $FfmpegExe -or $null -eq $FfprobeExe) {
        throw "Pinned FFmpeg archive did not contain ffmpeg.exe and ffprobe.exe."
    }
    $FfmpegBin = Join-Path $Root "tools\ffmpeg\windows\bin"
    New-Item -ItemType Directory -Force -Path $FfmpegBin | Out-Null
    Copy-Item -LiteralPath $FfmpegExe.FullName -Destination (Join-Path $FfmpegBin "ffmpeg.exe") -Force
    Copy-Item -LiteralPath $FfprobeExe.FullName -Destination (Join-Path $FfmpegBin "ffprobe.exe") -Force
    Write-Host "FFmpeg 8.1.2 CLI restored."

    # Poppler has its own pinned downloader + dependency-closure reducer.
    & (Join-Path $Root "tools\poppler\refresh_windows_runtime.ps1") -ProjectRoot $Root

    # Typst 0.15.1 Windows compiler. MiTeX package material is already committed.
    $TypstUrl = "https://github.com/typst/typst/releases/download/v0.15.1/typst-x86_64-pc-windows-msvc.zip"
    $TypstSha = "19ce3551153c2fe7ee9fa2f95208310c8f4d3209fedb699e0333faf8913f6736"
    $TypstZip = Join-Path $Temp "typst-x86_64-pc-windows-msvc.zip"
    $TypstExtract = Join-Path $Temp "typst"
    Get-VerifiedArchive $TypstUrl $TypstSha $TypstZip
    Expand-Archive -LiteralPath $TypstZip -DestinationPath $TypstExtract -Force
    $TypstExe = Get-ChildItem -LiteralPath $TypstExtract -Filter "typst.exe" -File -Recurse | Select-Object -First 1
    if ($null -eq $TypstExe) { throw "Pinned Typst archive did not contain typst.exe." }
    $TypstTarget = Join-Path $Root "tools\typst\windows\typst.exe"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $TypstTarget) | Out-Null
    Copy-Item -LiteralPath $TypstExe.FullName -Destination $TypstTarget -Force
    Write-Host "Typst 0.15.1 restored."

    Write-Host ""
    Write-Host "NotLight downloaded dependencies are ready."
    Write-Host "The downloaded runtime files are intentionally ignored by Git."
    Write-Host "You can now open project.godot in Godot 4.4.1."
}
finally {
    if (Test-Path -LiteralPath $Temp) {
        Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
