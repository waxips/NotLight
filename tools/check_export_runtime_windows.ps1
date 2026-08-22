param(
    [string]$BuildDir = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

function Invoke-NativeMerged([string]$Executable, [string[]]$Arguments) {
    # Windows PowerShell 5.1 can turn native stderr redirected with 2>&1 into
    # NativeCommandError records. With $ErrorActionPreference = "Stop" that
    # aborts the script even when the native process exits with code 0.
    # Poppler legitimately emits non-fatal diagnostics such as
    # "No display font for 'Symbol'" on some Windows installations, so native
    # process success is determined by its exit code and expected output files.
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $lines = @(& $Executable @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedPreference
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = (($lines | Out-String).Trim())
    }
}
if ([string]::IsNullOrWhiteSpace($BuildDir)) {
    $BuildDir = Join-Path $projectRoot "dist"
}
if ([System.IO.Path]::IsPathRooted($BuildDir)) {
    $BuildDir = [System.IO.Path]::GetFullPath($BuildDir)
}
else {
    $BuildDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $BuildDir))
}
if (-not (Test-Path -LiteralPath $BuildDir -PathType Container)) {
    throw "Export directory was not found: $BuildDir"
}

$required = @(
    "tools\ffmpeg\windows\bin\ffmpeg.exe",
    "tools\ffmpeg\windows\bin\ffprobe.exe",
    "tools\poppler\windows\Library\bin\pdfinfo.exe",
    "tools\poppler\windows\Library\bin\pdftoppm.exe",
    "tools\qpdf\windows\bin\qpdf.exe",
    "tools\qpdf\windows\bin\qpdf30.dll",
    "tools\typst\windows\typst.exe",
    "tools\typst\packages\local\mitex\0.2.7\typst.toml",
    "tools\typst\packages\local\mitex\0.2.7\mitex.wasm",
    "LICENSE",
    "COPYRIGHT",
    "README.md",
    "THIRD_PARTY_NOTICES.md",
    "CORRESPONDING_SOURCE.md",
    "RELEASE_COMPLIANCE.md",
    "THIRD_PARTY_COMPONENTS.json",
    "THIRD_PARTY_LICENSES\Godot-MIT.txt",
    "THIRD_PARTY_LICENSES\GODOT_COPYRIGHT.txt",
    "THIRD_PARTY_LICENSES\CC-BY-4.0.txt",
    "THIRD_PARTY_LICENSES\CC0-1.0.txt",
    "THIRD_PARTY_LICENSES\EIRTeam.FFmpeg-MIT.txt",
    "THIRD_PARTY_LICENSES\EIRTeam.FFmpeg-FFmpeg-LGPLv3.txt",
    "THIRD_PARTY_LICENSES\FFmpeg-GPLv3.txt",
    "THIRD_PARTY_LICENSES\Poppler-GPL-2.0.txt",
    "THIRD_PARTY_LICENSES\QPDF-Apache-2.0.txt",
    "THIRD_PARTY_LICENSES\QPDF-NOTICE.md",
    "THIRD_PARTY_LICENSES\Typst-Apache-2.0.txt",
    "THIRD_PARTY_LICENSES\Typst-NOTICE.txt",
    "THIRD_PARTY_LICENSES\MiTeX-Apache-2.0.txt"
)
foreach ($relative in $required) {
    $path = Join-Path $BuildDir $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Export runtime is incomplete. Missing: $relative"
    }
}

# qpdf uses the system-installed Microsoft Visual C++ runtime. Do not let copies
# from the upstream qpdf archive silently leak back into a NotLight release.
$qpdfBin = Join-Path $BuildDir "tools\qpdf\windows\bin"
$forbiddenVcRuntime = Get-ChildItem -LiteralPath $qpdfBin -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '^(?i:concrt140\.dll|msvcp140(?:_[^.]*)?\.dll|vcruntime140(?:_[^.]*)?\.dll)$'
}
if (@($forbiddenVcRuntime).Count -gt 0) {
    $names = ($forbiddenVcRuntime | ForEach-Object { $_.Name }) -join ", "
    throw "Exported qpdf runtime contains Microsoft VC runtime copies that NotLight intentionally does not redistribute: $names"
}

$manifestPath = Join-Path $BuildDir "NOTLIGHT_RUNTIME_MANIFEST.json"
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.schema -ne "notlight.export-runtime-manifest") {
        throw "Unexpected export runtime manifest schema: $($manifest.schema)"
    }
    if (@($manifest.missing_runtime).Count -gt 0 -or @($manifest.copy_failures).Count -gt 0) {
        throw "The export plugin reported missing runtime files or copy failures. See $manifestPath"
    }
}

$ffmpeg = Join-Path $BuildDir "tools\ffmpeg\windows\bin\ffmpeg.exe"
$ffprobe = Join-Path $BuildDir "tools\ffmpeg\windows\bin\ffprobe.exe"
$ffmpegResult = Invoke-NativeMerged $ffmpeg @("-version")
$ffmpegVersion = $ffmpegResult.Output
if ($ffmpegResult.ExitCode -ne 0 -or $ffmpegVersion -notmatch '(?i)^ffmpeg version') {
    throw "Exported ffmpeg failed to start.`n$ffmpegVersion"
}
$ffprobeResult = Invoke-NativeMerged $ffprobe @("-version")
$ffprobeVersion = $ffprobeResult.Output
if ($ffprobeResult.ExitCode -ne 0 -or $ffprobeVersion -notmatch '(?i)^ffprobe version') {
    throw "Exported ffprobe failed to start.`n$ffprobeVersion"
}

$fixture = Join-Path $projectRoot "tools\fixtures\export_runtime_smoke.pdf"
if (-not (Test-Path -LiteralPath $fixture -PathType Leaf)) {
    throw "PDF smoke fixture is missing: $fixture"
}
$pdfinfo = Join-Path $BuildDir "tools\poppler\windows\Library\bin\pdfinfo.exe"
$pdftoppm = Join-Path $BuildDir "tools\poppler\windows\Library\bin\pdftoppm.exe"
$pdfInfoResult = Invoke-NativeMerged $pdfinfo @($fixture)
$pdfInfoOutput = $pdfInfoResult.Output
if ($pdfInfoResult.ExitCode -ne 0 -or $pdfInfoOutput -notmatch '(?im)^Pages:\s+1\s*$') {
    throw "Exported Poppler pdfinfo failed.`n$pdfInfoOutput"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("notlight-export-runtime-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $ppmBase = Join-Path $tempRoot "page"
    $renderResult = Invoke-NativeMerged $pdftoppm @("-q", "-f", "1", "-l", "1", "-singlefile", "-png", "-scale-to", "256", $fixture, $ppmBase)
    $renderOutput = $renderResult.Output
    if ($renderResult.ExitCode -ne 0) {
        throw "Exported Poppler pdftoppm failed.`n$renderOutput"
    }
    if ($renderOutput -match "No display font for 'Symbol'|No display font for 'ZapfDingbats'") {
        Write-Warning "Poppler could not find an optional Base-14 Symbol/Dingbats display font. The smoke page still rendered successfully; PDFs with embedded fonts are unaffected. PDFs relying on unembedded Symbol/Dingbats may use substitution."
    }
    $pngPath = "$ppmBase.png"
    if (-not (Test-Path -LiteralPath $pngPath -PathType Leaf) -or (Get-Item -LiteralPath $pngPath).Length -le 0) {
        throw "Exported Poppler returned success but did not create the page image."
    }

    $qpdfRoot = Join-Path $BuildDir "tools\qpdf\windows"
    & (Join-Path $projectRoot "tools\check_qpdf_windows.ps1") -QpdfRoot $qpdfRoot
    if ($LASTEXITCODE -ne 0) { throw "Exported qpdf runtime validation failed." }
    $qpdf = Join-Path $qpdfRoot "bin\qpdf.exe"
    $optimized = Join-Path $tempRoot "optimized.pdf"
    $qpdfResult = Invoke-NativeMerged $qpdf @($fixture, "--compress-streams=y", "--recompress-flate", "--object-streams=generate", $optimized)
    $qpdfOutput = $qpdfResult.Output
    if ($qpdfResult.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $optimized -PathType Leaf)) {
        throw "Exported qpdf could not rewrite the smoke PDF.`n$qpdfOutput"
    }
    $qpdfCheckResult = Invoke-NativeMerged $qpdf @($optimized, "--check")
    $qpdfCheckOutput = $qpdfCheckResult.Output
    if ($qpdfCheckResult.ExitCode -notin @(0, 3)) {
        throw "Exported qpdf could not validate its output.`n$qpdfCheckOutput"
    }

    $typstRoot = Join-Path $BuildDir "tools\typst\windows"
    $packageRoot = Join-Path $BuildDir "tools\typst\packages"
    & (Join-Path $projectRoot "tools\check_formula_runtime_windows.ps1") -TypstRoot $typstRoot -PackageRoot $packageRoot
    if ($LASTEXITCODE -ne 0) { throw "Exported Typst/MiTeX runtime validation failed." }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "NotLight exported Windows runtime smoke test: OK"
Write-Host "Checked FFmpeg/ffprobe, Poppler PDF metadata/rendering, qpdf rewrite/check, and Typst+MiTeX SVG compilation."
Write-Host "Build directory: $BuildDir"
