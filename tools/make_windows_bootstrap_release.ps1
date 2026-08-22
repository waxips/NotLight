param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$BuildDir = "",
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if ([string]::IsNullOrWhiteSpace($BuildDir)) {
    $BuildDir = Join-Path $Root "dist"
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $Root "release_out"
}

$BuildDir = (Resolve-Path $BuildDir).Path
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$SafeVersion = ($Version -replace '[^0-9A-Za-z._-]', '-')
$PackageName = "NotLight-$SafeVersion-windows-x86_64"
$PackageDir = Join-Path $OutputRoot $PackageName
$ZipPath = Join-Path $OutputRoot ($PackageName + ".zip")

foreach ($Name in @("NotLight.exe", "NotLight.pck")) {
    if (-not (Test-Path -LiteralPath (Join-Path $BuildDir $Name) -PathType Leaf)) {
        throw "Build directory does not contain $Name`: $BuildDir"
    }
}

if (Test-Path -LiteralPath $PackageDir) {
    Remove-Item -LiteralPath $PackageDir -Recurse -Force
}
if (Test-Path -LiteralPath $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
}

Copy-Item -LiteralPath $BuildDir -Destination $PackageDir -Recurse -Force

# The full local build is smoke-tested with all runtime providers installed.
# The public bootstrap ZIP then removes the components that are downloaded from
# their pinned upstream providers during the recipient's first launch.
$RemovePaths = @(
    "addons\ffmpeg\win64",
    "addons\ffmpeg\linux64",
    "tools\ffmpeg\windows",
    "tools\poppler\windows",
    "tools\typst\windows"
)

foreach ($Relative in $RemovePaths) {
    $Path = Join-Path $PackageDir $Relative
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

# Godot exports the EIRTeam GDExtension DLL and declared dependency DLLs beside
# the executable. Strip those from the public bootstrap package as well. The
# first-run setup restores the pinned release copies to the same location.
$ExportedEirRuntimeFiles = @(
    "libgdffmpeg.windows.template_debug.x86_64.dll",
    "libgdffmpeg.windows.template_release.x86_64.dll",
    "avcodec-60.dll",
    "avfilter-9.dll",
    "avformat-60.dll",
    "avutil-58.dll",
    "swresample-4.dll",
    "swscale-7.dll"
)

foreach ($Name in $ExportedEirRuntimeFiles) {
    $Path = Join-Path $PackageDir $Name
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Remove-Item -LiteralPath $Path -Force
        Write-Host "Removed first-run EIRTeam runtime from public ZIP staging: $Name"
    }
}

# An optional Godot console wrapper is not part of the end-user package.
$ConsoleExe = Join-Path $PackageDir "NotLight.console.exe"
if (Test-Path -LiteralPath $ConsoleExe -PathType Leaf) {
    Remove-Item -LiteralPath $ConsoleExe -Force
}

# The full-runtime manifest describes the private smoke-test build and is not
# truthful after the public package has been stripped.
$OldManifest = Join-Path $PackageDir "NOTLIGHT_RUNTIME_MANIFEST.json"
if (Test-Path -LiteralPath $OldManifest -PathType Leaf) {
    Remove-Item -LiteralPath $OldManifest -Force
}

foreach ($Name in @(
    "00_START_HERE.txt",
    "START_NOTLIGHT.bat",
    "SETUP_WINDOWS_DEPENDENCIES.ps1",
    "README_WINDOWS.txt",
    "SOURCE_CODE.txt"
)) {
    $Source = Join-Path $Root "tools\release\$Name"
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Release support file is missing: $Source"
    }
    Copy-Item -LiteralPath $Source -Destination (Join-Path $PackageDir $Name) -Force
}

$ReleaseManifest = [ordered]@{
    schema = "notlight.public-windows-bootstrap"
    schema_version = 1
    version = $Version
    application = "NotLight.exe"
    starter = "START_NOTLIGHT.bat"
    downloaded_on_first_run = @(
        "EIRTeam.FFmpeg v1.1.4 Windows runtime",
        "Gyan FFmpeg 8.1.2 Essentials CLI (verified GitHub release mirror)",
        "Poppler Windows v26.02.0-0 audited runtime closure",
        "Typst 0.15.1 Windows executable"
    )
    included_runtime = @(
        "qpdf 12.4.0 qpdf.exe/qpdf30.dll",
        "MiTeX 0.2.7 local Typst package"
    )
}

$ReleaseManifest |
    ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (Join-Path $PackageDir "NOTLIGHT_RELEASE_MANIFEST.json") -Encoding UTF8

python (Join-Path $Root "tools\validate_windows_bootstrap_release.py") $PackageDir
if ($LASTEXITCODE -ne 0) {
    throw "Public Windows package validation failed."
}

Compress-Archive -LiteralPath $PackageDir -DestinationPath $ZipPath -CompressionLevel Optimal

$ZipHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ZipPath).Hash.ToLowerInvariant()
$ShaLine = "$ZipHash  $($PackageName).zip`n"
[System.IO.File]::WriteAllText(
    (Join-Path $OutputRoot "SHA256SUMS.txt"),
    $ShaLine,
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "Public Windows package ready: $ZipPath"
Write-Host "SHA-256: $ZipHash"
