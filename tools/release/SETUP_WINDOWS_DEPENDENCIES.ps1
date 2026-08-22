param(
    [switch]$QuietIfReady
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Marker = Join-Path $Root ".notlight-runtime-v1.json"

$RequiredFiles = @(
    "addons\ffmpeg\win64\libgdffmpeg.windows.template_release.x86_64.dll",
    "addons\ffmpeg\win64\avcodec-60.dll",
    "addons\ffmpeg\win64\avformat-60.dll",
    "addons\ffmpeg\win64\avutil-58.dll",
    "tools\ffmpeg\windows\bin\ffmpeg.exe",
    "tools\ffmpeg\windows\bin\ffprobe.exe",
    "tools\poppler\windows\Library\bin\pdfinfo.exe",
    "tools\poppler\windows\Library\bin\pdftoppm.exe",
    "tools\typst\windows\typst.exe"
)

function Test-RuntimeReady {
    foreach ($Relative in $RequiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $Relative) -PathType Leaf)) {
            return $false
        }
    }
    return $true
}

function Get-VerifiedArchive([string]$Url, [string]$ExpectedSha256, [string]$Destination) {
    Write-Host "Downloading $Url"
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Destination
    $Actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Destination).Hash.ToLowerInvariant()
    if ($Actual -ne $ExpectedSha256.ToLowerInvariant()) {
        throw "SHA-256 verification failed.`nExpected: $ExpectedSha256`nActual:   $Actual"
    }
    Write-Host "Verified SHA-256: $Actual"
}

function Replace-Directory([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Downloaded package is missing expected directory: $Source"
    }
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

if ((Test-Path -LiteralPath $Marker -PathType Leaf) -and (Test-RuntimeReady)) {
    if (-not $QuietIfReady) {
        Write-Host "NotLight dependencies are already installed."
    }
    exit 0
}

Write-Host ""
Write-Host "NotLight first-run setup"
Write-Host "------------------------"
Write-Host "NotLight itself is already installed."
Write-Host "This step downloads the pinned media/PDF/formula components directly from their upstream providers."
Write-Host "Downloaded archives are verified before they are installed."
Write-Host "An Internet connection is required for this first setup."
Write-Host ""

$Temp = Join-Path ([System.IO.Path]::GetTempPath()) ("notlight-runtime-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $Temp | Out-Null

try {
    # EIRTeam.FFmpeg v1.1.4 official release asset.
    $EirUrl = "https://github.com/EIRTeam/EIRTeam.FFmpeg/releases/download/autobuild-2025-11-12-13-44/eirteam-ffmpeg-1.1.4.zip"
    $EirSha = "1a8dbc4d7524172ca72517dac4ffb24965025c2f19067882be35376b75bc107c"
    $EirZip = Join-Path $Temp "eirteam-ffmpeg-1.1.4.zip"
    $EirExtract = Join-Path $Temp "eirteam"
    Get-VerifiedArchive $EirUrl $EirSha $EirZip
    Expand-Archive -LiteralPath $EirZip -DestinationPath $EirExtract -Force
    Replace-Directory (Join-Path $EirExtract "addons\ffmpeg\win64") (Join-Path $Root "addons\ffmpeg\win64")

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
        throw "Pinned FFmpeg archive does not contain ffmpeg.exe and ffprobe.exe."
    }
    $FfmpegBin = Join-Path $Root "tools\ffmpeg\windows\bin"
    New-Item -ItemType Directory -Force -Path $FfmpegBin | Out-Null
    Copy-Item -LiteralPath $FfmpegExe.FullName -Destination (Join-Path $FfmpegBin "ffmpeg.exe") -Force
    Copy-Item -LiteralPath $FfprobeExe.FullName -Destination (Join-Path $FfmpegBin "ffprobe.exe") -Force

    # Poppler 26.02.0 provider bundle. Keep only NotLight's audited dependency closure.
    $PopplerUrl = "https://github.com/oschwartz10612/poppler-windows/releases/download/v26.02.0-0/Release-26.02.0-0.zip"
    $PopplerSha = "993e4a94376ed712fafc7058d724ea0b943d118bbd2305cd9ed55174eb85cda5"
    $PopplerZip = Join-Path $Temp "Release-26.02.0-0.zip"
    $PopplerExtract = Join-Path $Temp "poppler"
    Get-VerifiedArchive $PopplerUrl $PopplerSha $PopplerZip
    Expand-Archive -LiteralPath $PopplerZip -DestinationPath $PopplerExtract -Force
    $ProviderRoot = Join-Path $PopplerExtract "poppler-26.02.0"
    $ProviderBin = Join-Path $ProviderRoot "Library\bin"
    $ProviderShare = Join-Path $ProviderRoot "share\poppler"
    $TargetRoot = Join-Path $Root "tools\poppler\windows"
    $TargetBin = Join-Path $TargetRoot "Library\bin"
    $TargetShare = Join-Path $TargetRoot "share\poppler"
    $RequiredPoppler = @(
        "pdfinfo.exe", "pdftoppm.exe", "poppler.dll", "freetype.dll", "zlib.dll",
        "jpeg8.dll", "libcurl.dll", "libssh2.dll", "libcrypto-3-x64.dll",
        "openjp2.dll", "lcms2.dll", "libpng16.dll", "tiff.dll", "deflate.dll",
        "Lerc.dll", "liblzma.dll", "zstd.dll"
    )
    if (Test-Path -LiteralPath $TargetRoot) { Remove-Item -LiteralPath $TargetRoot -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $TargetBin | Out-Null
    foreach ($Name in $RequiredPoppler) {
        $Source = Join-Path $ProviderBin $Name
        if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "Poppler archive is missing $Name" }
        Copy-Item -LiteralPath $Source -Destination (Join-Path $TargetBin $Name) -Force
    }
    if (-not (Test-Path -LiteralPath $ProviderShare -PathType Container)) { throw "Poppler data directory is missing." }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $TargetShare) | Out-Null
    Copy-Item -LiteralPath $ProviderShare -Destination $TargetShare -Recurse -Force

    # Typst 0.15.1. The MiTeX package is already included in the NotLight release.
    $TypstUrl = "https://github.com/typst/typst/releases/download/v0.15.1/typst-x86_64-pc-windows-msvc.zip"
    $TypstSha = "19ce3551153c2fe7ee9fa2f95208310c8f4d3209fedb699e0333faf8913f6736"
    $TypstZip = Join-Path $Temp "typst-x86_64-pc-windows-msvc.zip"
    $TypstExtract = Join-Path $Temp "typst"
    Get-VerifiedArchive $TypstUrl $TypstSha $TypstZip
    Expand-Archive -LiteralPath $TypstZip -DestinationPath $TypstExtract -Force
    $TypstExe = Get-ChildItem -LiteralPath $TypstExtract -Filter "typst.exe" -File -Recurse | Select-Object -First 1
    if ($null -eq $TypstExe) { throw "Pinned Typst archive does not contain typst.exe." }
    $TypstTarget = Join-Path $Root "tools\typst\windows\typst.exe"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $TypstTarget) | Out-Null
    Copy-Item -LiteralPath $TypstExe.FullName -Destination $TypstTarget -Force

    if (-not (Test-RuntimeReady)) {
        throw "Dependency setup completed downloads but one or more required runtime files are still missing."
    }

    $State = [ordered]@{
        schema = "notlight.windows-runtime-bootstrap"
        schema_version = 1
        installed_utc = [DateTime]::UtcNow.ToString("o")
        eirteam_ffmpeg = "1.1.4"
        ffmpeg_cli = "8.1.2 essentials"
        poppler = "26.02.0-0"
        typst = "0.15.1"
    }
    $State | ConvertTo-Json | Set-Content -LiteralPath $Marker -Encoding UTF8

    Write-Host ""
    Write-Host "Setup complete. NotLight is ready to start."
}
catch {
    Write-Host ""
    Write-Host "NotLight could not finish first-run setup." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Check your Internet connection and try START_NOTLIGHT.bat again."
    exit 1
}
finally {
    if (Test-Path -LiteralPath $Temp) {
        Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
