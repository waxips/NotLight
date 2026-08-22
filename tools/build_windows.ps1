param(
    [string]$Godot = "godot",
    [switch]$DebugBuild
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root "dist"
$ffmpegSource = Join-Path $root "tools\ffmpeg\windows\bin"
$ffmpegDist = Join-Path $dist "tools\ffmpeg\windows\bin"
$popplerSource = Join-Path $root "tools\poppler\windows"
$popplerDist = Join-Path $dist "tools\poppler\windows"
$exportRuntimeCheck = Join-Path $root "tools\check_export_runtime_windows.ps1"
$qpdfSource = Join-Path $root "tools\qpdf\windows"
$qpdfRuntimeSource = Join-Path $qpdfSource "bin"
$qpdfDist = Join-Path $dist "tools\qpdf\windows\bin"
$qpdfCheck = Join-Path $root "tools\check_qpdf_windows.ps1"
$typstSource = Join-Path $root "tools\typst\windows"
$typstPackageRoot = Join-Path $root "tools\typst\packages"
$mitexSource = Join-Path $typstPackageRoot "local\mitex\0.2.7"
$typstDist = Join-Path $dist "tools\typst\windows"
$typstPackageDistRoot = Join-Path $dist "tools\typst\packages"
$mitexDist = Join-Path $typstPackageDistRoot "local\mitex\0.2.7"
$formulaRuntimeCheck = Join-Path $root "tools\check_formula_runtime_windows.ps1"

foreach ($name in @("ffmpeg.exe", "ffprobe.exe")) {
    $path = Join-Path $ffmpegSource $name
    if (-not (Test-Path $path)) {
        throw "Missing $path. Put the bundled FFmpeg binaries in tools/ffmpeg/windows/bin first."
    }
}

foreach ($relative in @("Library\bin\pdfinfo.exe", "Library\bin\pdftoppm.exe", "share\poppler\COPYING")) {
    $path = Join-Path $popplerSource $relative
    if (-not (Test-Path $path)) {
        throw "Missing $path. Restore the pinned Poppler runtime bundle first."
    }
}

if (-not (Test-Path $qpdfCheck)) {
    throw "Missing qpdf runtime validator: $qpdfCheck"
}
& $qpdfCheck -QpdfRoot $qpdfSource

$qpdfExe = Get-ChildItem -Path $qpdfSource -Filter "qpdf.exe" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $qpdfExe) {
    throw "Missing qpdf.exe below $qpdfSource. Extract the pinned qpdf-12.4.0-msvc64.zip runtime there before release packaging."
}

if (-not (Test-Path $formulaRuntimeCheck)) {
    throw "Missing Typst/MiTeX formula runtime validator: $formulaRuntimeCheck"
}
& $formulaRuntimeCheck -TypstRoot $typstSource -PackageRoot $typstPackageRoot

if (Test-Path $dist) {
    Remove-Item $dist -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$preset = "Windows Desktop"
$exportFlag = if ($DebugBuild) { "--export-debug" } else { "--export-release" }
$exePath = Join-Path $dist "NotLightBoard.exe"

& $Godot --headless --path $root $exportFlag $preset $exePath
if ($LASTEXITCODE -ne 0) {
    throw "Godot export failed with exit code $LASTEXITCODE"
}

# The editor export plugin performs these copies for normal GUI exports. Repeat the
# same layout here after deleting any plugin-produced directory first, so the
# headless release path is deterministic and never creates nested windows/windows
# directories when both mechanisms are active.
foreach ($runtimePath in @($ffmpegDist, $popplerDist, $qpdfDist, $typstDist, $mitexDist)) {
    if (Test-Path $runtimePath) {
        Remove-Item $runtimePath -Recurse -Force
    }
}

New-Item -ItemType Directory -Force -Path $ffmpegDist | Out-Null
Copy-Item (Join-Path $ffmpegSource "ffmpeg.exe") $ffmpegDist
Copy-Item (Join-Path $ffmpegSource "ffprobe.exe") $ffmpegDist

New-Item -ItemType Directory -Force -Path (Join-Path $popplerDist "Library") | Out-Null
Copy-Item (Join-Path $popplerSource "Library\bin") (Join-Path $popplerDist "Library\bin") -Recurse
New-Item -ItemType Directory -Force -Path (Join-Path $popplerDist "share") | Out-Null
Copy-Item (Join-Path $popplerSource "share\poppler") (Join-Path $popplerDist "share\poppler") -Recurse

New-Item -ItemType Directory -Force -Path $qpdfDist | Out-Null
Copy-Item (Join-Path $qpdfRuntimeSource "qpdf.exe") (Join-Path $qpdfDist "qpdf.exe")
Copy-Item (Join-Path $qpdfRuntimeSource "qpdf30.dll") (Join-Path $qpdfDist "qpdf30.dll")

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $typstDist) | Out-Null
Copy-Item $typstSource $typstDist -Recurse
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $mitexDist) | Out-Null
Copy-Item $mitexSource $mitexDist -Recurse

foreach ($name in @("LICENSE", "COPYRIGHT", "README.md", "THIRD_PARTY_NOTICES.md", "CORRESPONDING_SOURCE.md", "RELEASE_COMPLIANCE.md", "THIRD_PARTY_COMPONENTS.json")) {
    $source = Join-Path $root $name
    if (Test-Path $source) { Copy-Item $source $dist }
}
if (Test-Path (Join-Path $root "THIRD_PARTY_LICENSES")) {
    $licenseDist = Join-Path $dist "THIRD_PARTY_LICENSES"
    if (Test-Path $licenseDist) { Remove-Item $licenseDist -Recurse -Force }
    Copy-Item (Join-Path $root "THIRD_PARTY_LICENSES") $dist -Recurse
}
if (Test-Path (Join-Path $root "tools\ffmpeg\SOURCE_INFO.md")) {
    Copy-Item (Join-Path $root "tools\ffmpeg\SOURCE_INFO.md") (Join-Path $dist "FFMPEG_SOURCE_INFO.md")
}
if (Test-Path (Join-Path $root "addons\ffmpeg\SOURCE_INFO.md")) {
    Copy-Item (Join-Path $root "addons\ffmpeg\SOURCE_INFO.md") (Join-Path $dist "EIRTEAM_FFMPEG_SOURCE_INFO.md")
}
if (Test-Path (Join-Path $root "tools\ffmpeg\windows\GYAN_BUILD_README.txt")) {
    Copy-Item (Join-Path $root "tools\ffmpeg\windows\GYAN_BUILD_README.txt") (Join-Path $dist "FFMPEG_BUILD_README.txt")
}
if (Test-Path (Join-Path $root "tools\poppler\SOURCE_INFO.md")) {
    Copy-Item (Join-Path $root "tools\poppler\SOURCE_INFO.md") (Join-Path $dist "POPPLER_SOURCE_INFO.md")
}
if (Test-Path (Join-Path $root "tools\qpdf\SOURCE_INFO.md")) {
    Copy-Item (Join-Path $root "tools\qpdf\SOURCE_INFO.md") (Join-Path $dist "QPDF_SOURCE_INFO.md")
}
if (Test-Path (Join-Path $root "tools\typst\SOURCE_INFO.md")) {
    Copy-Item (Join-Path $root "tools\typst\SOURCE_INFO.md") (Join-Path $dist "FORMULA_RUNTIME_SOURCE_INFO.md")
}
if (-not (Test-Path $exportRuntimeCheck)) {
    throw "Missing exported-runtime smoke checker: $exportRuntimeCheck"
}
& $exportRuntimeCheck -BuildDir $dist
if ($LASTEXITCODE -ne 0) {
    throw "Exported runtime smoke test failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "Build ready: $dist"
Write-Host "FFmpeg sidecar: $ffmpegDist"
Write-Host "Poppler sidecar: $popplerDist"
Write-Host "qpdf sidecar: $qpdfDist"
Write-Host "Typst sidecar: $typstDist"
Write-Host "MiTeX local package: $mitexDist"
