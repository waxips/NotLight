param(
    [string]$BuildDir = "",
    [string]$ExportedExe = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($BuildDir)) {
    $BuildDir = Join-Path $projectRoot "dist"
}
elseif (-not [System.IO.Path]::IsPathRooted($BuildDir)) {
    # Resolve user-provided relative paths against the visible PowerShell
    # location, not the host process working directory (which may be System32).
    $BuildDir = Join-Path (Get-Location).Path $BuildDir
}
$BuildDir = [System.IO.Path]::GetFullPath($BuildDir)

if (-not (Test-Path -LiteralPath $BuildDir -PathType Container)) {
    throw "Export directory was not found: $BuildDir`nExport the Windows preset into this directory first, then run this script again."
}

if (-not [string]::IsNullOrWhiteSpace($ExportedExe)) {
    if (-not [System.IO.Path]::IsPathRooted($ExportedExe)) {
        $ExportedExe = Join-Path $BuildDir $ExportedExe
    }
    $ExportedExe = [System.IO.Path]::GetFullPath($ExportedExe)
    if (-not (Test-Path -LiteralPath $ExportedExe -PathType Leaf)) {
        throw "The exported EXE passed to the packager was not found: $ExportedExe"
    }
}
else {
    $candidate = Get-ChildItem -LiteralPath $BuildDir -Filter "*.exe" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '(?i)\.console\.exe$' } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if ($null -eq $candidate) {
        throw "No exported EXE was found in: $BuildDir`nExport the Windows preset into this directory first."
    }
    $ExportedExe = $candidate.FullName
}
Write-Host "Using exported executable: $(Split-Path -Leaf $ExportedExe)"

function Assert-NoReparsePoints([string]$Root) {
    $rootItem = Get-Item -LiteralPath $Root -Force
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing runtime source that is a symlink/junction/reparse point: $Root"
    }

    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($rootItem.FullName)
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        foreach ($child in Get-ChildItem -LiteralPath $current -Force) {
            if (($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing symlink/junction/reparse point inside runtime source: $($child.FullName)"
            }
            if ($child.PSIsContainer) {
                $pending.Push($child.FullName)
            }
        }
    }
}

function Copy-CleanDirectory([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        throw "Required runtime directory is missing from the project: $Source"
    }
    Assert-NoReparsePoints $Source
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

function Copy-RequiredFile([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Required runtime file is missing from the project: $Source"
    }
    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

Write-Host ""
Write-Host "Packaging NotLight Windows runtime..."
Write-Host "Project: $projectRoot"
Write-Host "Export : $BuildDir"

# FFmpeg CLI: only executables needed by NotLight's sidecar wrapper.
$ffmpegSource = Join-Path $projectRoot "tools\ffmpeg\windows\bin"
$ffmpegDest = Join-Path $BuildDir "tools\ffmpeg\windows\bin"
if (Test-Path -LiteralPath $ffmpegDest) { Remove-Item -LiteralPath $ffmpegDest -Recurse -Force }
New-Item -ItemType Directory -Force -Path $ffmpegDest | Out-Null
Copy-RequiredFile (Join-Path $ffmpegSource "ffmpeg.exe") (Join-Path $ffmpegDest "ffmpeg.exe")
Copy-RequiredFile (Join-Path $ffmpegSource "ffprobe.exe") (Join-Path $ffmpegDest "ffprobe.exe")

# Poppler: executable/DLL runtime and poppler-data.
Copy-CleanDirectory (Join-Path $projectRoot "tools\poppler\windows\Library\bin") (Join-Path $BuildDir "tools\poppler\windows\Library\bin")
Copy-CleanDirectory (Join-Path $projectRoot "tools\poppler\windows\share\poppler") (Join-Path $BuildDir "tools\poppler\windows\share\poppler")

# qpdf runtime only. Keep the MSVC runtime as a system prerequisite rather
# than redistributing copied msvcp/vcruntime/concrt DLLs from the upstream ZIP.
$qpdfSource = Join-Path $projectRoot "tools\qpdf\windows\bin"
$qpdfDest = Join-Path $BuildDir "tools\qpdf\windows\bin"
if (Test-Path -LiteralPath $qpdfDest) { Remove-Item -LiteralPath $qpdfDest -Recurse -Force }
New-Item -ItemType Directory -Force -Path $qpdfDest | Out-Null
Copy-RequiredFile (Join-Path $qpdfSource "qpdf.exe") (Join-Path $qpdfDest "qpdf.exe")
Copy-RequiredFile (Join-Path $qpdfSource "qpdf30.dll") (Join-Path $qpdfDest "qpdf30.dll")

# Typst binary + offline MiTeX package.
Copy-CleanDirectory (Join-Path $projectRoot "tools\typst\windows") (Join-Path $BuildDir "tools\typst\windows")
Copy-CleanDirectory (Join-Path $projectRoot "tools\typst\packages\local\mitex\0.2.7") (Join-Path $BuildDir "tools\typst\packages\local\mitex\0.2.7")

# Legal/provenance files are copied beside the application.
foreach ($name in @("LICENSE", "COPYRIGHT", "README.md", "THIRD_PARTY_NOTICES.md", "CORRESPONDING_SOURCE.md", "RELEASE_COMPLIANCE.md", "THIRD_PARTY_COMPONENTS.json")) {
    $source = Join-Path $projectRoot $name
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $BuildDir $name) -Force
    }
}
$licensesSource = Join-Path $projectRoot "THIRD_PARTY_LICENSES"
if (Test-Path -LiteralPath $licensesSource -PathType Container) {
    Copy-CleanDirectory $licensesSource (Join-Path $BuildDir "THIRD_PARTY_LICENSES")
}
$provenance = @(
    @{ Source = "tools\ffmpeg\SOURCE_INFO.md"; Destination = "FFMPEG_SOURCE_INFO.md" },
    @{ Source = "addons\ffmpeg\SOURCE_INFO.md"; Destination = "EIRTEAM_FFMPEG_SOURCE_INFO.md" },
    @{ Source = "tools\ffmpeg\windows\GYAN_BUILD_README.txt"; Destination = "FFMPEG_BUILD_README.txt" },
    @{ Source = "tools\poppler\SOURCE_INFO.md"; Destination = "POPPLER_SOURCE_INFO.md" },
    @{ Source = "tools\qpdf\SOURCE_INFO.md"; Destination = "QPDF_SOURCE_INFO.md" },
    @{ Source = "tools\typst\SOURCE_INFO.md"; Destination = "FORMULA_RUNTIME_SOURCE_INFO.md" }
)
foreach ($item in $provenance) {
    $source = Join-Path $projectRoot $item.Source
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $BuildDir $item.Destination) -Force
    }
}

$manifest = [ordered]@{
    schema = "notlight.export-runtime-manifest"
    version = 2
    packaged_at_utc = [DateTime]::UtcNow.ToString("o")
    build_directory = $BuildDir
    runtime = [ordered]@{
        ffmpeg = "tools/ffmpeg/windows/bin"
        poppler = "tools/poppler/windows"
        qpdf = "tools/qpdf/windows/bin"
        typst = "tools/typst/windows"
        mitex = "tools/typst/packages/local/mitex/0.2.7"
    }
    missing_runtime = @()
    copy_failures = @()
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $BuildDir "NOTLIGHT_RUNTIME_MANIFEST.json") -Encoding UTF8

$checker = Join-Path $projectRoot "tools\check_export_runtime_windows.ps1"
if (-not (Test-Path -LiteralPath $checker -PathType Leaf)) {
    throw "Runtime checker is missing: $checker"
}

Write-Host ""
Write-Host "Runtime files copied. Running real smoke tests from the exported folder..."
& $checker -BuildDir $BuildDir
if ($LASTEXITCODE -ne 0) {
    throw "Exported runtime smoke test failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "SUCCESS. The dist folder is ready."
Write-Host "Run: $ExportedExe"
Write-Host "For distribution, archive the whole folder, not only the EXE."
