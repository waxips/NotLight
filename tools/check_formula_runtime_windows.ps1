param(
    [string]$TypstRoot = "",
    [string]$PackageRoot = "",
    [string]$TypstArchivePath = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

function Invoke-NativeMerged([string]$Executable, [string[]]$Arguments) {
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $lines = @(& $Executable @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedPreference
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = (($lines | Out-String).Trim()) }
}
if ([string]::IsNullOrWhiteSpace($TypstRoot)) { $TypstRoot = Join-Path $projectRoot "tools\typst\windows" }
if ([string]::IsNullOrWhiteSpace($PackageRoot)) { $PackageRoot = Join-Path $projectRoot "tools\typst\packages" }

$expectedTypstVersion = "0.15.1"
$expectedTypstArchiveName = "typst-x86_64-pc-windows-msvc.zip"
# GitHub's v0.15.1 x86_64 Windows asset. Kept here as an installation-time
# integrity pin; SOURCE_INFO.md records the upstream release URL/provenance.
$expectedTypstArchiveSha256 = "19ce3551153c2fe7ee9fa2f95208310c8f4d3209fedb699e0333faf8913f6736"
$packageDirectory = Join-Path $PackageRoot "local\mitex\0.2.7"
$metadataPath = Join-Path $packageDirectory ".NOTLIGHT_MITEX_PACKAGE_INFO.json"


function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

function Get-ContentDigest([string]$Directory) {
    $files = @(Get-ChildItem -LiteralPath $Directory -File -Recurse -Force | Where-Object { $_.Name -ne ".NOTLIGHT_MITEX_PACKAGE_INFO.json" } | Sort-Object { $_.FullName.Substring($Directory.Length).Replace('\','/') })
    $builder = New-Object System.Text.StringBuilder
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($Directory.Length).TrimStart('\','/').Replace('\','/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        [void]$builder.Append($relative); [void]$builder.Append("`t"); [void]$builder.Append($hash); [void]$builder.Append("`n")
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

if (-not [string]::IsNullOrWhiteSpace($TypstArchivePath)) {
    if (-not (Test-Path -LiteralPath $TypstArchivePath -PathType Leaf)) { throw "Typst archive was not found: $TypstArchivePath" }
    if ((Split-Path -Leaf $TypstArchivePath) -ne $expectedTypstArchiveName) { throw "Unexpected Typst archive name. Expected $expectedTypstArchiveName." }
    $archiveHash = (Get-FileHash -LiteralPath $TypstArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($archiveHash -ne $expectedTypstArchiveSha256) { throw "Typst archive SHA-256 mismatch. Expected $expectedTypstArchiveSha256, got $archiveHash." }
    Write-Host "Typst archive checksum OK: $archiveHash"
}

if (-not (Test-Path -LiteralPath $TypstRoot -PathType Container)) { throw "Typst runtime directory was not found: $TypstRoot" }
$typstExe = Get-ChildItem -LiteralPath $TypstRoot -Filter "typst.exe" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $typstExe) { throw "typst.exe was not found below $TypstRoot. Extract $expectedTypstArchiveName there." }

$versionResult = Invoke-NativeMerged $typstExe.FullName @("--version")
$versionOutput = $versionResult.Output
if ($versionResult.ExitCode -ne 0) { throw "typst --version failed with exit code $($versionResult.ExitCode)." }
$versionMatch = [regex]::Match($versionOutput, '(?i)\btypst\s+([0-9]+\.[0-9]+\.[0-9]+)\b')
if (-not $versionMatch.Success) { throw "Could not parse Typst version from: $versionOutput" }
$actualVersion = $versionMatch.Groups[1].Value
if ($actualVersion -ne $expectedTypstVersion) { throw "Unexpected Typst version $actualVersion. NotLight is pinned to $expectedTypstVersion." }

foreach ($required in @("typst.toml", "LICENSE", "lib.typ", "mitex.typ", "mitex.wasm", "specs\mod.typ", ".NOTLIGHT_MITEX_PACKAGE_INFO.json")) {
    if (-not (Test-Path -LiteralPath (Join-Path $packageDirectory $required) -PathType Leaf)) { throw "Prepared MiTeX package is missing: $required" }
}
$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
if ($metadata.schema -ne "notlight.mitex-package-provenance" -or $metadata.package -ne "mitex" -or $metadata.version -ne "0.2.7") { throw "MiTeX provenance metadata is invalid." }
$actualPackageDigest = Get-ContentDigest $packageDirectory
if ($actualPackageDigest -ne ([string]$metadata.content_digest_sha256).ToLowerInvariant()) { throw "MiTeX installed content digest mismatch. Re-run prepare_mitex_windows.ps1 from the official package archive." }

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("notlight-formula-check-" + [Guid]::NewGuid().ToString("N"))
$cacheRoot = Join-Path $tempRoot "package-cache"
New-Item -ItemType Directory -Path $tempRoot | Out-Null
New-Item -ItemType Directory -Path $cacheRoot | Out-Null
try {
    $formulaText = @'
\frac{-b \pm \sqrt{b^2-4ac}}{2a}
'@
    $wrapperText = @'
#import "@local/mitex:0.2.7": mi, mitex
#set page(width: auto, height: auto, margin: 16pt, fill: none)
#set text(size: 18pt)
#let source = read("formula.txt")
#box(inset: 20pt)[#mitex(source)]
'@
    Write-Utf8NoBom (Join-Path $tempRoot "formula.txt") $formulaText.TrimEnd([char]13, [char]10)
    Write-Utf8NoBom (Join-Path $tempRoot "formula.typ") $wrapperText

    $output = Join-Path $tempRoot "formula.svg"
    $args = @(
        "compile", "--format", "svg",
        "--root", $tempRoot,
        "--package-path", $PackageRoot,
        "--package-cache-path", $cacheRoot,
        "--ignore-system-fonts",
        "--creation-timestamp", "0",
        "--jobs", "1",
        "--diagnostic-format", "short",
        (Join-Path $tempRoot "formula.typ"), $output
    )
    $compileResult = Invoke-NativeMerged $typstExe.FullName $args
    $compileOutput = $compileResult.Output
    if ($compileResult.ExitCode -ne 0) { throw "Offline Typst+MiTeX smoke compile failed:`n$compileOutput" }
    if (-not (Test-Path -LiteralPath $output -PathType Leaf)) { throw "Typst did not create the expected SVG." }
    $svgHead = Get-Content -LiteralPath $output -Raw
    if ($svgHead -notmatch '<svg\b') { throw "Typst output is not an SVG document." }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

$typstBytes = $typstExe.Length
$packageBytes = [int64]((Get-ChildItem -LiteralPath $packageDirectory -File -Recurse -Force | Measure-Object -Property Length -Sum).Sum)
Write-Host "Typst runtime OK: $($typstExe.FullName)"
Write-Host "Typst version: $actualVersion"
Write-Host "MiTeX local package: 0.2.7"
Write-Host "MiTeX content digest: $actualPackageDigest"
Write-Host "Offline/local-only SVG formula smoke compile: OK"
Write-Host "Typst executable bytes: $typstBytes"
Write-Host "MiTeX package bytes: $packageBytes"
