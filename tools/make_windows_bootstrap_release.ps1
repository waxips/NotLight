param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$BuildDir = "",
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($BuildDir)) { $BuildDir = Join-Path $Root "dist" }
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $Root "release_out" }
$BuildDir = (Resolve-Path $BuildDir).Path
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$SafeVersion = ($Version -replace '[^0-9A-Za-z._-]', '-')
$PackageName = "NotLight-$SafeVersion-windows-x86_64"
$PackageDir = Join-Path $OutputRoot $PackageName
$ZipPath = Join-Path $OutputRoot ($PackageName + ".zip")

if (-not (Test-Path -LiteralPath (Join-Path $BuildDir "NotLight.exe") -PathType Leaf)) {
    throw "Build directory does not contain NotLight.exe: $BuildDir"
}
if (-not (Test-Path -LiteralPath (Join-Path $BuildDir "NotLight.pck") -PathType Leaf)) {
    throw "Build directory does not contain NotLight.pck: $BuildDir"
}

if (Test-Path -LiteralPath $PackageDir) { Remove-Item -LiteralPath $PackageDir -Recurse -Force }
if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
Copy-Item -LiteralPath $BuildDir -Destination $PackageDir -Recurse -Force

# The full local build is smoke-tested with these runtimes first. The public ZIP
# then removes downloaded copyleft/runtime-provider binaries; START_NOTLIGHT.bat
# fetches the exact pinned upstream packages on the recipient's computer.
$RemovePaths = @(
    "addons\ffmpeg\win64",
    "addons\ffmpeg\linux64",
    "tools\ffmpeg\windows",
    "tools\poppler\windows",
    "tools\typst\windows"
)
foreach ($Relative in $RemovePaths) {
    $Path = Join-Path $PackageDir $Relative
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
}

# The full-runtime manifest describes the private smoke-test build and is no
# longer truthful after the public package is stripped.
$OldManifest = Join-Path $PackageDir "NOTLIGHT_RUNTIME_MANIFEST.json"
if (Test-Path -LiteralPath $OldManifest) { Remove-Item -LiteralPath $OldManifest -Force }

foreach ($Name in @("00_START_HERE.txt", "START_NOTLIGHT.bat", "SETUP_WINDOWS_DEPENDENCIES.ps1", "README_WINDOWS.txt", "SOURCE_CODE.txt")) {
    Copy-Item -LiteralPath (Join-Path $Root "tools\release\$Name") -Destination (Join-Path $PackageDir $Name) -Force
}

$ReleaseManifest = [ordered]@{
    schema = "notlight.public-windows-bootstrap"
    schema_version = 1
    version = $Version
    application = "NotLight.exe"
    starter = "START_NOTLIGHT.bat"
    downloaded_on_first_run = @(
        "EIRTeam.FFmpeg v1.1.4 Windows runtime",
        "Gyan.dev FFmpeg 8.1.2 Essentials CLI",
        "Poppler Windows v26.02.0-0 audited runtime closure",
        "Typst 0.15.1 Windows executable"
    )
    included_runtime = @(
        "qpdf 12.4.0 qpdf.exe/qpdf30.dll",
        "MiTeX 0.2.7 local Typst package"
    )
}
$ReleaseManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $PackageDir "NOTLIGHT_RELEASE_MANIFEST.json") -Encoding UTF8

python (Join-Path $Root "tools\validate_windows_bootstrap_release.py") $PackageDir
if ($LASTEXITCODE -ne 0) { throw "Public Windows package validation failed." }

Compress-Archive -LiteralPath $PackageDir -DestinationPath $ZipPath -CompressionLevel Optimal
$ZipHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ZipPath).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText((Join-Path $OutputRoot "SHA256SUMS.txt"), "$ZipHash  $($PackageName).zip`n", [System.Text.UTF8Encoding]::new($false))

Write-Host "Public Windows package ready: $ZipPath"
Write-Host "SHA-256: $ZipHash"
