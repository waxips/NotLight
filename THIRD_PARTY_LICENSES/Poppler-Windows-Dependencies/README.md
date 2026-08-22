# Poppler Windows dependency notices

These notices cover the DLL dependency closure retained beside NotLight's pinned
Poppler `pdfinfo.exe` and `pdftoppm.exe` Windows tools. The binaries come from
`oschwartz10612/poppler-windows` release `v26.02.0-0`; that project repackages
conda-forge binaries. The packaging repository's MIT license does **not**
relicense Poppler or its dependencies.

| Component | Version | Runtime file(s) | License used for redistribution | Notice file |
| --- | --- | --- | --- | --- |
| FreeType | 2.14.3 | `freetype.dll` | FTL | `FreeType-FTL.txt` |
| zlib | 1.3.2 | `zlib.dll` | Zlib | `zlib-Zlib.txt` |
| libjpeg-turbo | 3.1.4.1 | `jpeg8.dll` | IJG/BSD-style | `libjpeg-turbo-IJG.txt` |
| curl | 8.20.0 | `libcurl.dll` | curl | `curl-license.txt` |
| OpenSSL | 3.6.2 | `libcrypto-3-x64.dll` | Apache-2.0 | `OpenSSL-Apache-2.0.txt` |
| LERC | provider-bundled build | `Lerc.dll` | Apache-2.0 | `LERC-Apache-2.0.txt` |
| OpenJPEG | 2.5.4 | `openjp2.dll` | BSD-2 | `OpenJPEG-BSD-2-Clause.txt` |
| libpng | 1.6.58 | `libpng16.dll` | libpng | `libpng-license.txt` |
| LibTIFF | 4.7.1 | `tiff.dll` | Hylafax | `libtiff-license.txt` |
| XZ Utils / liblzma | 5.8.3 | `liblzma.dll` | 0BSD | `XZ-libLZMA-0BSD.txt` |
| libssh2 | 1.11.1 | `libssh2.dll` | BSD3 | `libssh2-BSD-3-Clause.txt` |
| Zstandard (zstd) | 1.5.7 | `zstd.dll` | BSD-3-clause | `zstd-BSD-3-Clause.txt` |
| libdeflate | provider-bundled build | `deflate.dll` | Expat | `libdeflate-MIT.txt` |
| Little CMS 2 | 2.19.0 | `lcms2.dll` | MIT | `LittleCMS2-MIT.txt` |

`libcurl.dll` pulls in `libssh2.dll`, which pulls in `libcrypto-3-x64.dll`;
`tiff.dll` pulls in zstd, liblzma, LERC, libdeflate, zlib and jpeg8. Those
transitive libraries are therefore retained even though Poppler does not import
all of them directly.

Microsoft `MSVCP140.dll` / `VCRUNTIME140*.dll` are not included here. They are
provided by the supported Microsoft Visual C++ v14 x64 Redistributable
prerequisite.

See `tools/poppler/SOURCE_INFO.md` for exact provider provenance and the
deterministic refresh command. This directory is release-maintenance material,
not legal advice.
