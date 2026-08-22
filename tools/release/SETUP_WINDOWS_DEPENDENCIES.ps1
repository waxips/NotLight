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

# In an exported Godot application the EIRTeam GDExtension DLL and its declared
# Windows dependencies live beside NotLight.exe. Command-line helper tools live
# below tools/.
$RequiredFiles = @(
    "libgdffmpeg.windows.template_release.x86_64.dll",
    "avcodec-60.dll",
    "avfilter-9.dll",
    "avformat-60.dll",
    "avutil-58.dll",
    "swresample-4.dll",
    "swscale-7.dll",
    "tools\ffmpeg\windows\bin\ffmpeg.exe",
    "tools\ffmpeg\windows\bin\ffprobe.exe",
    "tools\poppler\windows\Library\bin\pdfinfo.exe",
    "tools\poppler\windows\Library\bin\pdftoppm.exe",
    "tools\typst\windows\typst.exe"
)

function Test-RuntimeReady {
    foreach ($Relative in $RequiredFiles) {
        $Path = Join-Path $Root $Relative
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return $false
        }
    }
    return $true
}

function Get-VerifiedArchive {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    Write-Host "Downloading: $Url"
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Destination

    $Actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Destination).Hash.ToLowerInvariant()
    $Expected = $ExpectedSha256.ToLowerInvariant()
    if ($Actual -ne $Expected) {
        throw "SHA-256 verification failed.`nExpected: $Expected`nActual:   $Actual"
    }
    Write-Host "SHA-256 OK: $Actual"
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
Write-Host "This one-time step downloads the pinned media, PDF and formula components."
Write-Host "Every downloaded archive is verified with SHA-256 before installation."
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

    Get-VerifiedArchive -Url $EirUrl -ExpectedSha256 $EirSha -Destination $EirZip
    Expand-Archive -LiteralPath $EirZip -DestinationPath $EirExtract -Force

    $EirRuntimeSource = Join-Path $EirExtract "addons\ffmpeg\win64"
    $EirRuntimeFiles = @(
        "libgdffmpeg.windows.template_release.x86_64.dll",
        "avcodec-60.dll",
        "avfilter-9.dll",
        "avformat-60.dll",
        "avutil-58.dll",
        "swresample-4.dll",
        "swscale-7.dll"
    )

    foreach ($Name in $EirRuntimeFiles) {
        $Source = Join-Path $EirRuntimeSource $Name
        if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
            throw "EIRTeam.FFmpeg archive is missing required Windows runtime: $Name"
        }
        Copy-Item -LiteralPath $Source -Destination (Join-Path $Root $Name) -Force
    }
    Write-Host "EIRTeam.FFmpeg v1.1.4 runtime installed."

    # Gyan FFmpeg 8.1.2 Essentials CLI, using the versioned GitHub release mirror.
    $FfmpegUrl = "https://github.com/GyanD/codexffmpeg/releases/download/8.1.2/ffmpeg-8.1.2-essentials_build.zip"
    $FfmpegSha = "db580001caa24ac104c8cb856cd113a87b0a443f7bdf47d8c12b1d740584a2ec"
    $FfmpegZip = Join-Path $Temp "ffmpeg-8.1.2-essentials_build.zip"
    $FfmpegExtract = Join-Path $Temp "ffmpeg-cli"

    Get-VerifiedArchive -Url $FfmpegUrl -ExpectedSha256 $FfmpegSha -Destination $FfmpegZip
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
    Write-Host "FFmpeg CLI 8.1.2 installed."

    # Poppler 26.02.0 provider bundle. Keep only NotLight's audited closure.
    $PopplerUrl = "https://github.com/oschwartz10612/poppler-windows/releases/download/v26.02.0-0/Release-26.02.0-0.zip"
    $PopplerSha = "993e4a94376ed712fafc7058d724ea0b943d118bbd2305cd9ed55174eb85cda5"
    $PopplerZip = Join-Path $Temp "Release-26.02.0-0.zip"
    $PopplerExtract = Join-Path $Temp "poppler"

    Get-VerifiedArchive -Url $PopplerUrl -ExpectedSha256 $PopplerSha -Destination $PopplerZip
    Expand-Archive -LiteralPath $PopplerZip -DestinationPath $PopplerExtract -Force

    $ProviderRoot = Join-Path $PopplerExtract "poppler-26.02.0"
    $ProviderBin = Join-Path $ProviderRoot "Library\bin"
    $ProviderShare = Join-Path $ProviderRoot "share\poppler"

    $TargetRoot = Join-Path $Root "tools\poppler\windows"
    $TargetBin = Join-Path $TargetRoot "Library\bin"
    $TargetShare = Join-Path $TargetRoot "share\poppler"

    $RequiredPoppler = @(
        "pdfinfo.exe",
        "pdftoppm.exe",
        "poppler.dll",
        "freetype.dll",
        "zlib.dll",
        "jpeg8.dll",
        "libcurl.dll",
        "libssh2.dll",
        "libcrypto-3-x64.dll",
        "openjp2.dll",
        "lcms2.dll",
        "libpng16.dll",
        "tiff.dll",
        "deflate.dll",
        "Lerc.dll",
        "liblzma.dll",
        "zstd.dll"
    )

    if (Test-Path -LiteralPath $TargetRoot) {
        Remove-Item -LiteralPath $TargetRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $TargetBin | Out-Null

    foreach ($Name in $RequiredPoppler) {
        $Source = Join-Path $ProviderBin $Name
        if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
            throw "Poppler archive is missing required runtime file: $Name"
        }
        Copy-Item -LiteralPath $Source -Destination (Join-Path $TargetBin $Name) -Force
    }

    if (-not (Test-Path -LiteralPath $ProviderShare -PathType Container)) {
        throw "Poppler data directory is missing."
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $TargetShare) | Out-Null
    Copy-Item -LiteralPath $ProviderShare -Destination $TargetShare -Recurse -Force
    Write-Host "Poppler 26.02.0-0 runtime installed."

    # Typst 0.15.1. MiTeX 0.2.7 is already bundled as source/package data.
    $TypstUrl = "https://github.com/typst/typst/releases/download/v0.15.1/typst-x86_64-pc-windows-msvc.zip"
    $TypstSha = "19ce3551153c2fe7ee9fa2f95208310c8f4d3209fedb699e0333faf8913f6736"
    $TypstZip = Join-Path $Temp "typst-x86_64-pc-windows-msvc.zip"
    $TypstExtract = Join-Path $Temp "typst"

    Get-VerifiedArchive -Url $TypstUrl -ExpectedSha256 $TypstSha -Destination $TypstZip
    Expand-Archive -LiteralPath $TypstZip -DestinationPath $TypstExtract -Force

    $TypstExe = Get-ChildItem -LiteralPath $TypstExtract -Filter "typst.exe" -File -Recurse | Select-Object -First 1
    if ($null -eq $TypstExe) {
        throw "Pinned Typst archive does not contain typst.exe."
    }

    $TypstTarget = Join-Path $Root "tools\typst\windows\typst.exe"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $TypstTarget) | Out-Null
    Copy-Item -LiteralPath $TypstExe.FullName -Destination $TypstTarget -Force
    Write-Host "Typst 0.15.1 installed."

    if (-not (Test-RuntimeReady)) {
        $Missing = @(
            foreach ($Relative in $RequiredFiles) {
                if (-not (Test-Path -LiteralPath (Join-Path $Root $Relative) -PathType Leaf)) {
                    $Relative
                }
            }
        )
        throw "Setup finished downloads but required runtime files are still missing: $($Missing -join ', ')"
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
    exit 0
}
catch {
    Write-Host ""
    Write-Host "NotLight could not finish first-run setup." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Check your Internet connection and run START_NOTLIGHT.bat again."
    exit 1
}
finally {
    if (Test-Path -LiteralPath $Temp) {
        Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
