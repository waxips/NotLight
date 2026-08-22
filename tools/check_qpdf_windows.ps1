param(
    [string]$QpdfRoot = "",
    [string]$ArchivePath = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

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
if ([string]::IsNullOrWhiteSpace($QpdfRoot)) {
    $QpdfRoot = Join-Path $root "tools\qpdf\windows"
}

$expectedVersion = "12.4.0"
$expectedArchiveName = "qpdf-12.4.0-msvc64.zip"
$expectedArchiveSha256 = "5bcb25353f7e6df92b5625dbcfe52a5c34a2a5fba2d1a8b98b8a6a0972c3ff72"

if (-not [string]::IsNullOrWhiteSpace($ArchivePath)) {
    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
        throw "qpdf archive was not found: $ArchivePath"
    }
    $archiveName = Split-Path -Leaf $ArchivePath
    if ($archiveName -ne $expectedArchiveName) {
        throw "Unexpected qpdf archive name '$archiveName'. Expected '$expectedArchiveName'."
    }
    $actualArchiveSha256 = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualArchiveSha256 -ne $expectedArchiveSha256) {
        throw "qpdf archive SHA-256 mismatch. Expected $expectedArchiveSha256, got $actualArchiveSha256."
    }
    Write-Host "qpdf archive checksum OK: $actualArchiveSha256"
}

if (-not (Test-Path -LiteralPath $QpdfRoot -PathType Container)) {
    throw "qpdf runtime directory was not found: $QpdfRoot"
}

$qpdfExe = Get-ChildItem -LiteralPath $QpdfRoot -Filter "qpdf.exe" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $qpdfExe) {
    throw "qpdf.exe was not found below $QpdfRoot. Extract $expectedArchiveName there and keep the official runtime layout."
}

$versionResult = Invoke-NativeMerged $qpdfExe.FullName @("--version")
$versionOutput = $versionResult.Output
if ($versionResult.ExitCode -ne 0) {
    throw "qpdf --version failed with exit code $($versionResult.ExitCode) at $($qpdfExe.FullName)."
}
$versionMatch = [regex]::Match($versionOutput, '(?m)\bqpdf\s+version\s+([0-9]+\.[0-9]+\.[0-9]+)\b')
if (-not $versionMatch.Success) {
    throw "Could not parse qpdf version from: $versionOutput"
}
$actualVersion = $versionMatch.Groups[1].Value
if ($actualVersion -ne $expectedVersion) {
    throw "Unexpected qpdf version $actualVersion. This project is pinned to qpdf $expectedVersion."
}

Write-Host "qpdf runtime OK: $($qpdfExe.FullName)"
Write-Host "qpdf version: $actualVersion"
