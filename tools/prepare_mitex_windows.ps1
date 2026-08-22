param(
    [Parameter(Mandatory = $true)]
    [string]$ArchivePath,
    [string]$PackageRoot = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = Join-Path $projectRoot "tools\typst\packages"
}

$expectedArchiveName = "mitex-0.2.7.tar.gz"
$expectedPackage = "mitex"
$expectedVersion = "0.2.7"
$expectedLicense = "Apache-2.0"
$maxEntries = 4096
$maxExtractedBytes = 8MB
$requiredFiles = @(
    "typst.toml",
    "LICENSE",
    "lib.typ",
    "mitex.typ",
    "mitex.wasm",
    "specs\mod.typ"
)


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
        [void]$builder.Append($relative)
        [void]$builder.Append("`t")
        [void]$builder.Append($hash)
        [void]$builder.Append("`n")
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

$ArchivePath = [System.IO.Path]::GetFullPath($ArchivePath)
$PackageRoot = [System.IO.Path]::GetFullPath($PackageRoot)
if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
    throw "MiTeX package archive was not found: $ArchivePath"
}
$archiveName = Split-Path -Leaf $ArchivePath
if ($archiveName -ne $expectedArchiveName) {
    throw "Unexpected MiTeX archive '$archiveName'. Expected '$expectedArchiveName'."
}

$tarCommand = Get-Command "tar.exe" -ErrorAction SilentlyContinue
if ($null -eq $tarCommand) {
    throw "Windows tar.exe was not found. Current Windows 10/11 normally includes it. Install/extract MiTeX manually only if you understand the local-package layout documented in tools/typst/packages/PLACE_MITEX_HERE.md."
}

New-Item -ItemType Directory -Force -Path $PackageRoot | Out-Null
$targetDirectory = Join-Path $PackageRoot "local\mitex\0.2.7"
if (Test-Path -LiteralPath $targetDirectory) {
    if (-not $Force) {
        throw "Prepared MiTeX package already exists: $targetDirectory. Re-run with -Force only if you intentionally want to replace it."
    }
}

Write-Host "Inspecting MiTeX package archive before extraction..."
$entries = @(& $tarCommand.Source -tzf $ArchivePath 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "tar.exe could not list $ArchivePath (exit code $LASTEXITCODE)."
}
if ($entries.Count -lt 5 -or $entries.Count -gt $maxEntries) {
    throw "Unexpected MiTeX archive entry count: $($entries.Count). Safety bound is 5..$maxEntries."
}

# Refuse symlinks/hardlinks/special nodes before extraction. The post-extraction
# ReparsePoint check remains as a second Windows-specific guard, but checking the
# tar entry type first prevents a link from redirecting a later archive write.
$verboseEntries = @(& $tarCommand.Source -tvzf $ArchivePath 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "tar.exe could not inspect entry types in $ArchivePath (exit code $LASTEXITCODE)."
}
foreach ($rawVerboseEntry in $verboseEntries) {
    $verboseEntry = ([string]$rawVerboseEntry).TrimStart()
    if ([string]::IsNullOrWhiteSpace($verboseEntry)) { continue }
    $entryType = $verboseEntry.Substring(0, 1)
    if ($entryType -ne "-" -and $entryType -ne "d") {
        throw "MiTeX archive contains a link or special entry. Only regular files/directories are accepted: $rawVerboseEntry"
    }
}

$seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($rawEntry in $entries) {
    $entry = ([string]$rawEntry).Trim()
    while ($entry.StartsWith("./", [System.StringComparison]::Ordinal)) { $entry = $entry.Substring(2) }
    if ([string]::IsNullOrWhiteSpace($entry)) { continue }
    $normalized = $entry.Replace('\','/')
    if ($normalized.StartsWith("/", [System.StringComparison]::Ordinal) -or
        $normalized.Contains(":") -or
        $normalized -eq ".." -or
        $normalized.StartsWith("../", [System.StringComparison]::Ordinal) -or
        $normalized.Contains("/../")) {
        throw "Unsafe path in MiTeX archive: $entry"
    }
    if (-not $seen.Add($normalized)) {
        throw "Duplicate MiTeX archive entry detected (case-insensitive Windows path): $entry"
    }
}

$archiveSha256 = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
$stagingRoot = Join-Path $PackageRoot (".prepare-mitex-{0}" -f [Guid]::NewGuid().ToString("N"))
$installStaging = Join-Path $PackageRoot (".install-mitex-{0}" -f [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $stagingRoot | Out-Null
try {
    & $tarCommand.Source -xzf $ArchivePath -C $stagingRoot
    if ($LASTEXITCODE -ne 0) {
        throw "tar.exe extraction failed with exit code $LASTEXITCODE."
    }

    $reparsePoints = @(Get-ChildItem -LiteralPath $stagingRoot -Recurse -Force -ErrorAction Stop | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 })
    if ($reparsePoints.Count -ne 0) {
        throw "The extracted MiTeX package contains a reparse point/symlink. Refusing to install it."
    }

    $manifestCandidates = @(Get-ChildItem -LiteralPath $stagingRoot -Filter "typst.toml" -File -Recurse -Force)
    if ($manifestCandidates.Count -ne 1) {
        throw "Expected exactly one typst.toml in the MiTeX archive, found $($manifestCandidates.Count)."
    }
    $sourceDirectory = $manifestCandidates[0].Directory.FullName
    foreach ($required in $requiredFiles) {
        $requiredPath = Join-Path $sourceDirectory $required
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "MiTeX package is missing required file: $required"
        }
    }

    $wasmPath = Join-Path $sourceDirectory "mitex.wasm"
    $wasmStream = [System.IO.File]::OpenRead($wasmPath)
    try {
        if ($wasmStream.Length -lt 8 -or $wasmStream.Length -gt 4MB) {
            throw "MiTeX WASM plugin size is outside the expected safety bound."
        }
        $wasmHeader = New-Object byte[] 4
        if ($wasmStream.Read($wasmHeader, 0, 4) -ne 4 -or
            $wasmHeader[0] -ne 0x00 -or $wasmHeader[1] -ne 0x61 -or
            $wasmHeader[2] -ne 0x73 -or $wasmHeader[3] -ne 0x6d) {
            throw "mitex.wasm does not have a valid WebAssembly header."
        }
    }
    finally {
        $wasmStream.Dispose()
    }

    $manifestText = Get-Content -LiteralPath (Join-Path $sourceDirectory "typst.toml") -Raw
    if ($manifestText -notmatch '(?m)^\s*name\s*=\s*["'']mitex["'']\s*$') { throw "typst.toml does not identify package 'mitex'." }
    if ($manifestText -notmatch '(?m)^\s*version\s*=\s*["'']0\.2\.7["'']\s*$') { throw "typst.toml does not identify MiTeX version 0.2.7." }
    if ($manifestText -notmatch '(?m)^\s*license\s*=\s*["'']Apache-2\.0["'']\s*$') { throw "typst.toml does not declare the expected Apache-2.0 license." }

    $files = @(Get-ChildItem -LiteralPath $sourceDirectory -File -Recurse -Force)
    $totalBytes = [int64](($files | Measure-Object -Property Length -Sum).Sum)
    if ($files.Count -gt $maxEntries -or $totalBytes -le 0 -or $totalBytes -gt $maxExtractedBytes) {
        throw "Unexpected extracted MiTeX package size: $($files.Count) files, $totalBytes bytes."
    }

    foreach ($typFile in @($files | Where-Object { $_.Extension -eq ".typ" })) {
        $typText = Get-Content -LiteralPath $typFile.FullName -Raw
        if ($typText -match '@(?:preview|packages)/') {
            throw "MiTeX package contains a remote Typst package import in $($typFile.FullName). NotLight formula runtime must stay local-only."
        }
    }

    New-Item -ItemType Directory -Path $installStaging | Out-Null
    Get-ChildItem -LiteralPath $sourceDirectory -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $installStaging -Recurse -Force }

    $contentDigest = Get-ContentDigest $installStaging
    $metadata = [ordered]@{
        schema = "notlight.mitex-package-provenance"
        schema_version = 1
        package = $expectedPackage
        version = $expectedVersion
        license = $expectedLicense
        source_url = "https://packages.typst.org/preview/mitex-0.2.7.tar.gz"
        source_archive = $expectedArchiveName
        source_archive_sha256 = $archiveSha256
        content_digest_sha256 = $contentDigest
        file_count = $files.Count
        total_bytes = $totalBytes
        prepared_utc = [DateTime]::UtcNow.ToString("o")
    }
    $metadataJson = $metadata | ConvertTo-Json -Depth 4
    Write-Utf8NoBom (Join-Path $installStaging ".NOTLIGHT_MITEX_PACKAGE_INFO.json") $metadataJson

    $targetParent = Split-Path -Parent $targetDirectory
    New-Item -ItemType Directory -Force -Path $targetParent | Out-Null
    $backupDirectory = Join-Path $PackageRoot (".backup-mitex-{0}" -f [Guid]::NewGuid().ToString("N"))
    $hadExisting = Test-Path -LiteralPath $targetDirectory -PathType Container
    try {
        if ($hadExisting) {
            Move-Item -LiteralPath $targetDirectory -Destination $backupDirectory
        }
        Move-Item -LiteralPath $installStaging -Destination $targetDirectory
        if (Test-Path -LiteralPath $backupDirectory) {
            Remove-Item -LiteralPath $backupDirectory -Recurse -Force
        }
    }
    catch {
        if (-not (Test-Path -LiteralPath $targetDirectory) -and (Test-Path -LiteralPath $backupDirectory)) {
            Move-Item -LiteralPath $backupDirectory -Destination $targetDirectory -ErrorAction SilentlyContinue
        }
        throw
    }

    Write-Host ""
    Write-Host "MiTeX local package prepared successfully."
    Write-Host "Installed directory: $targetDirectory"
    Write-Host "Files: $($files.Count)"
    Write-Host "Extracted bytes: $totalBytes"
    Write-Host "Source archive SHA-256 (recorded for provenance): $archiveSha256"
    Write-Host "Installed content digest: $contentDigest"
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $installStaging) { Remove-Item -LiteralPath $installStaging -Recurse -Force -ErrorAction SilentlyContinue }
}
