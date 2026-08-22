param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

$Version = "26.02.0-0"
$PopplerVersion = "26.02.0"
$ArchiveUrl = "https://github.com/oschwartz10612/poppler-windows/releases/download/v26.02.0-0/Release-26.02.0-0.zip"
$ExpectedSha256 = "993e4a94376ed712fafc7058d724ea0b943d118bbd2305cd9ed55174eb85cda5"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
} else {
    $ProjectRoot = (Resolve-Path $ProjectRoot).Path
}

$TargetRoot = Join-Path $ProjectRoot "tools\poppler\windows"
$TargetBin = Join-Path $TargetRoot "Library\bin"
$TargetShare = Join-Path $TargetRoot "share\poppler"
$PopplerRoot = Join-Path $ProjectRoot "tools\poppler"
$HashesPath = Join-Path $PopplerRoot "RUNTIME_SHA256SUMS.txt"
$Gpl3Path = Join-Path $ProjectRoot "THIRD_PARTY_LICENSES\Poppler-Data-GPL-3.0.txt"

$RequiredBinFiles = @(
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

$Temp = Join-Path ([System.IO.Path]::GetTempPath()) ("notlight-poppler-" + [Guid]::NewGuid().ToString("N"))
$Zip = Join-Path $Temp "Release-$Version.zip"
$Extract = Join-Path $Temp "extract"

try {
    New-Item -ItemType Directory -Force -Path $Temp, $Extract | Out-Null
    Write-Host "Downloading pinned Poppler Windows bundle $Version..."
    Invoke-WebRequest -Uri $ArchiveUrl -OutFile $Zip

    $ActualSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Zip).Hash.ToLowerInvariant()
    if ($ActualSha256 -ne $ExpectedSha256) {
        throw "Poppler ZIP SHA-256 mismatch. Expected $ExpectedSha256, got $ActualSha256"
    }

    Expand-Archive -LiteralPath $Zip -DestinationPath $Extract -Force
    $ProviderRoot = Join-Path $Extract "poppler-$PopplerVersion"
    $ProviderBin = Join-Path $ProviderRoot "Library\bin"
    $ProviderShare = Join-Path $ProviderRoot "share\poppler"

    if (-not (Test-Path -LiteralPath $ProviderBin -PathType Container)) {
        throw "Provider Library/bin directory was not found: $ProviderBin"
    }
    if (-not (Test-Path -LiteralPath $ProviderShare -PathType Container)) {
        throw "Provider share/poppler directory was not found: $ProviderShare"
    }

    if (Test-Path -LiteralPath $TargetBin) { Remove-Item -LiteralPath $TargetBin -Recurse -Force }
    if (Test-Path -LiteralPath $TargetShare) { Remove-Item -LiteralPath $TargetShare -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $TargetBin | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path $TargetShare -Parent) | Out-Null

    foreach ($Name in $RequiredBinFiles) {
        $Source = Join-Path $ProviderBin $Name
        if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
            throw "Pinned provider archive is missing required file: $Name"
        }
        Copy-Item -LiteralPath $Source -Destination (Join-Path $TargetBin $Name) -Force
    }

    Copy-Item -LiteralPath $ProviderShare -Destination $TargetShare -Recurse -Force
    if (-not (Test-Path -LiteralPath $Gpl3Path -PathType Leaf)) {
        throw "Missing local GPLv3 text required for poppler-data notice completion: $Gpl3Path"
    }
    Copy-Item -LiteralPath $Gpl3Path -Destination (Join-Path $TargetShare "COPYING.gpl3") -Force

    $HashLines = foreach ($Name in ($RequiredBinFiles | Sort-Object)) {
        $File = Join-Path $TargetBin $Name
        $Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $File).Hash.ToLowerInvariant()
        "$Hash  windows/Library/bin/$Name"
    }
    $ShareFiles = Get-ChildItem -LiteralPath $TargetShare -Recurse -File | Sort-Object FullName
    foreach ($File in $ShareFiles) {
        $Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $File.FullName).Hash.ToLowerInvariant()
        $Relative = $File.FullName.Substring($PopplerRoot.Length).TrimStart("\").Replace("\", "/")
        $HashLines += "$Hash  $Relative"
    }
    [System.IO.File]::WriteAllLines($HashesPath, $HashLines, [System.Text.UTF8Encoding]::new($false))

    Write-Host "Poppler runtime refreshed and verified."
    Write-Host "Archive SHA-256: $ActualSha256"
    Write-Host "Retained binary files: $($RequiredBinFiles.Count)"
    Write-Host "Hashes: $HashesPath"
}
finally {
    if (Test-Path -LiteralPath $Temp) {
        Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
