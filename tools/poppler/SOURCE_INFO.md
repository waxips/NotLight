# Poppler Windows runtime provenance

NotLight uses Poppler's `pdfinfo` and `pdftoppm` command-line utilities as a
local PDF metadata/rasterization backend.

## Pinned binary provider

- Poppler utility version: **26.02.0**
- Windows package provider: `oschwartz10612/poppler-windows`
- Provider release: **v26.02.0-0**
- Provider release commit shown by GitHub: `a6703d8`
- Release archive: `Release-26.02.0-0.zip`
- Release archive SHA-256:
  `993e4a94376ed712fafc7058d724ea0b943d118bbd2305cd9ed55174eb85cda5`
- Provider URL:
  `https://github.com/oschwartz10612/poppler-windows/releases/tag/v26.02.0-0`
- Archive URL:
  `https://github.com/oschwartz10612/poppler-windows/releases/download/v26.02.0-0/Release-26.02.0-0.zip`

The provider repository states that it packages compiled Poppler binaries and
dependencies from conda-forge and adds upstream poppler-data. Its packaging
script explicitly copies the same dependency families retained here. The
packaging repository itself is MIT-licensed; that MIT license does not relicense
Poppler or the bundled dependency DLLs.

The conda-forge Poppler package is identified as GPL-2.0-or-later. The
`26.02.0` Windows package line includes build `win-64/poppler-26.02.0-h4b9d284_3.conda`.

## Retained runtime

NotLight deliberately ships only the recursive local PE dependency closure of
`pdfinfo.exe` and `pdftoppm.exe`:

- `pdfinfo.exe`
- `pdftoppm.exe`
- `poppler.dll`
- `freetype.dll`
- `zlib.dll`
- `jpeg8.dll`
- `libcurl.dll`
- `libssh2.dll`
- `libcrypto-3-x64.dll`
- `openjp2.dll`
- `lcms2.dll`
- `libpng16.dll`
- `tiff.dll`
- `deflate.dll`
- `Lerc.dll`
- `liblzma.dll`
- `zstd.dll`

The broader provider ZIP also contains files not needed by these two tools
(Cairo, Fontconfig, Iconv, Expat, Pixman, Poppler GLib/CPP, and duplicate
libtiff/libzstd names). Those files are intentionally excluded from NotLight.

`RUNTIME_SHA256SUMS.txt` records hashes of the exact pinned runtime copies. The public GitHub source repository does not commit the `tools/poppler/windows/` runtime directory; `refresh_windows_runtime.ps1` restores it locally from the verified provider archive.

## Deterministic refresh

On Windows, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\poppler\refresh_windows_runtime.ps1
```

The script downloads the pinned provider ZIP, refuses it unless its SHA-256
matches the value above, replaces the local Poppler runtime with only the
retained dependency closure, restores the complete poppler-data directory, and
regenerates `RUNTIME_SHA256SUMS.txt`.

This is the preferred way to refresh the binaries immediately before producing
a public GitHub release.

## poppler-data

The provider release packages upstream `poppler-data` **0.4.12**. Its bundled
`COPYING` states that CMaps use the Adobe redistribution grant and that Glyph &
Cog mapping data may be redistributed under GPLv2 or GPLv3. The provider payload
contains `COPYING.gpl2` but omits the referenced GPLv3 text, so NotLight adds
`COPYING.gpl3` from the standard GPLv3 license text to keep the notice set
self-contained.

Copies of the relevant notices are also retained under `THIRD_PARTY_LICENSES/`.

## Windows runtime prerequisite

The retained executables/DLLs import `MSVCP140.dll`, `VCRUNTIME140.dll`, and
`VCRUNTIME140_1.dll`. NotLight does not copy those DLLs out of unrelated
third-party ZIPs. The supported Microsoft Visual C++ v14 x64 Redistributable is
a Windows prerequisite.

## Source/build material for a public release

For conservative GPL release hygiene, publish the matching NotLight source and
keep corresponding Poppler source/build material available with the binary
release:

- Poppler upstream: `https://poppler.freedesktop.org/`
- Poppler 26.02.0 release/source
- conda-forge build recipe: `https://github.com/conda-forge/poppler-feedstock`
- Windows packaging recipe: `https://github.com/oschwartz10612/poppler-windows`
- poppler-data 0.4.12 source: `https://poppler.freedesktop.org/poppler-data-0.4.12.tar.gz`

The retained dependency license notices are in
`THIRD_PARTY_LICENSES/Poppler-Windows-Dependencies/`.

This file is engineering/provenance documentation, not legal advice.
