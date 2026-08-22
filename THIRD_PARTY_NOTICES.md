<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Third-party notices

This file records third-party components present in the NotLight source tree, included in the Windows distribution, or installed by NotLight's first-run Windows dependency setup. It is a project-maintenance/compliance aid, not legal advice. Release packaging copies this file, `THIRD_PARTY_COMPONENTS.json`, `CORRESPONDING_SOURCE.md`, `RELEASE_COMPLIANCE.md`, and `THIRD_PARTY_LICENSES/` next to the exported application.

A component being listed here does **not** mean every release obligation has already been satisfied. `RELEASE_COMPLIANCE.md` is the publish gate and deliberately marks unresolved source/provenance work as a blocker.

## Godot Engine 4.4.1

NotLight is built with Godot Engine 4.4.1. Godot is distributed under the MIT license.

Copyright (c) 2014-present Godot Engine contributors.  
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

- Upstream: https://github.com/godotengine/godot
- Engine license: `THIRD_PARTY_LICENSES/Godot-MIT.txt`
- Godot 4.4.1 bundled third-party copyright/license inventory: `THIRD_PARTY_LICENSES/GODOT_COPYRIGHT.txt`

The `GODOT_COPYRIGHT.txt` inventory is kept with the same engine line so notices for libraries incorporated into the official export template are not lost.

## EIRTeam.FFmpeg GDExtension and its FFmpeg shared libraries

NotLight uses the EIRTeam.FFmpeg GDExtension wrapper, licensed under MIT.

Copyright (c) 2018 Álex Román (EIRTeam).

- Upstream: https://github.com/EIRTeam/EIRTeam.FFmpeg
- Upstream release: **v1.1.4**
- Release tag: `autobuild-2025-11-12-13-44`
- Commit: `270e661`
- Official asset: `eirteam-ffmpeg-1.1.4.zip`
- Verified asset SHA-256: `1a8dbc4d7524172ca72517dac4ffb24965025c2f19067882be35376b75bc107c`
- Wrapper license: `THIRD_PARTY_LICENSES/EIRTeam.FFmpeg-MIT.txt`
- Exact file-hash/provenance record: `addons/ffmpeg/SOURCE_INFO.md`

The Windows and Linux runtime binaries used by NotLight were compared with the
official v1.1.4 release asset and **all 16 runtime binaries match byte-for-byte**.
The local `ffmpeg.gdextension` only omits upstream Android/macOS entries for
platform binaries NotLight does not ship.

The same official asset contains FFmpeg shared libraries identifying build
`N-111611-g5b11ee9429-20230724`. Their embedded configure line uses
`--enable-version3`, `--enable-shared`, and does not use `--enable-gpl` or
`--enable-nonfree`; the FFmpeg library layer therefore identifies as an
**LGPLv3-or-later** build. The relevant LGPL text is retained at
`THIRD_PARTY_LICENSES/EIRTeam.FFmpeg-FFmpeg-LGPLv3.txt`. External-library
licenses linked into that FFmpeg build also remain applicable.

For the public **source repository**, NotLight intentionally does not commit the
EIRTeam DLL/SO runtime files. The public **Windows ZIP also does not contain
these DLLs**. `START_NOTLIGHT.bat` downloads the exact official v1.1.4 asset on
the recipient machine and verifies its SHA-256 before installing the Windows
runtime. If a future NotLight release directly bundles these FFmpeg libraries,
the applicable LGPL source/notice/replacement review must be reopened.

## FFmpeg CLI — Gyan.dev FFmpeg 8.1.2 Essentials

NotLight uses pinned Gyan.dev FFmpeg 8.1.2 Essentials Windows x64 `ffmpeg.exe` and `ffprobe.exe` as external tools. The selected build is GPLv3 and includes GPL-enabled encoding libraries such as libx264/libx265. These executables are **not included in the public source repository or the public Windows ZIP**; the first-run Windows setup downloads the pinned provider archive directly on the recipient machine and verifies its SHA-256.

- FFmpeg upstream/source: https://ffmpeg.org/ and https://github.com/FFmpeg/FFmpeg
- Build provider: https://www.gyan.dev/ffmpeg/builds/
- License: `THIRD_PARTY_LICENSES/FFmpeg-GPLv3.txt`
- Exact artifact/source/hash information: `tools/ffmpeg/SOURCE_INFO.md`
- Source-delivery map: `CORRESPONDING_SOURCE.md`

If a future NotLight package directly redistributes this object code, retain the license notices and provide the exact Corresponding Source/build material by a GPLv3-compliant method. The current public bootstrap package avoids that direct redistribution and instead downloads the pinned provider archive on the recipient machine.

## Poppler PDF tools and poppler-data

NotLight uses Poppler command-line utilities `pdfinfo` and `pdftoppm` as a local PDF backend. The Windows runtime is pinned to `oschwartz10612/poppler-windows` release `v26.02.0-0`, packaging Poppler 26.02.0 and conda-forge dependencies together with upstream `poppler-data` 0.4.12.

The local development/smoke-test runtime retains only the utilities, `poppler.dll`, and the dependency closure needed by those utilities. Unused provider DLLs are intentionally excluded. The public NotLight Windows ZIP does **not** contain this Poppler runtime; first-run setup downloads the pinned provider package directly on the recipient machine.

- Poppler upstream: https://poppler.freedesktop.org/
- Windows package provider: https://github.com/oschwartz10612/poppler-windows
- Pinned provider release: `v26.02.0-0`
- Provider release ZIP SHA-256: `993e4a94376ed712fafc7058d724ea0b943d118bbd2305cd9ed55174eb85cda5`
- Poppler license: GPL-2.0-or-later
- Poppler GPL text: `THIRD_PARTY_LICENSES/Poppler-GPL-2.0.txt`
- Retained Windows dependency notices: `THIRD_PARTY_LICENSES/Poppler-Windows-Dependencies/`
- poppler-data notices: `THIRD_PARTY_LICENSES/Poppler-Data-COPYING.txt`, `THIRD_PARTY_LICENSES/Poppler-Data-Adobe.txt`, `THIRD_PARTY_LICENSES/Poppler-Data-GPL-3.0.txt`
- Exact runtime provenance/refresh procedure: `tools/poppler/SOURCE_INFO.md`

The Windows binaries depend on the Microsoft Visual C++ v14 x64 runtime. NotLight does not redistribute ad-hoc copies of `MSVCP140.dll` or `VCRUNTIME140*.dll`; the supported Microsoft Visual C++ Redistributable is treated as a Windows prerequisite.

If a future NotLight package directly redistributes this Poppler object code, keep the matching Poppler source/build recipe available to recipients in accordance with the applicable GPL terms. The current public bootstrap ZIP installs Poppler from the pinned upstream provider on the recipient machine.

## qpdf 12.4.0 PDF optimization backend

NotLight uses qpdf as an optional local backend for conservative PDF optimization. The pinned Windows package is the official qpdf 12.4.0 `qpdf-12.4.0-msvc64.zip`, licensed under Apache-2.0.

qpdf is copyright (c) 2005-2021 Jay Berkenbilt and (c) 2022-2026 Jay Berkenbilt and Manfred Holger. The upstream NOTICE also records qtest, Rijndael/public-domain and sphlib notices.

- Upstream: https://github.com/qpdf/qpdf
- Release: `v12.4.0`
- License: `THIRD_PARTY_LICENSES/QPDF-Apache-2.0.txt`
- NOTICE: `THIRD_PARTY_LICENSES/QPDF-NOTICE.md`
- Pinned artifact/hash information: `tools/qpdf/SOURCE_INFO.md`

NotLight's release package includes only `qpdf.exe` and `qpdf30.dll`. Microsoft `concrt140.dll`, `msvcp140*.dll` and `vcruntime140*.dll` copied from the upstream ZIP are intentionally **not** redistributed; users install the supported Microsoft Visual C++ Redistributable x64 separately.

## Typst 0.15.1 + MiTeX 0.2.7 formula backend

NotLight renders formulas locally through a pinned Typst/MiTeX stack:

- Typst compiler 0.15.1 — Apache-2.0; the compiler NOTICE and third-party attributions are retained in `THIRD_PARTY_LICENSES/Typst-NOTICE.txt` and beside `typst.exe` where applicable.
- MiTeX package 0.2.7 — Apache-2.0; the package manifest names Myriad-Dreamin, OrangeX4, Enter-tainer and Shichien as authors.

Upstream projects:

- https://github.com/typst/typst
- https://github.com/mitex-rs/mitex
- https://typst.app/universe/package/mitex/

License copies are stored at `THIRD_PARTY_LICENSES/Typst-Apache-2.0.txt` and `THIRD_PARTY_LICENSES/MiTeX-Apache-2.0.txt`. `tools/typst/SOURCE_INFO.md` records pinned versions, hashes and the offline local-package contract.

The large `typst.exe` binary is not committed to the source repository or included in the public Windows ZIP. First-run setup downloads the pinned official Typst archive on the recipient machine and verifies its SHA-256. The small MiTeX package material is included with its Apache-2.0 license and provenance.

## NotLight ambient phrase reference catalog (CC0-1.0)

`localization/ambient/phrases.json` is retained as an author/reference catalog for the Hub ambient phrases. The running application resolves those phrases through the normal localization catalogs instead of loading this JSON file directly. The phrase texts in the reference catalog are dedicated under **CC0-1.0**.

- Catalog: `localization/ambient/phrases.json`
- License text: `THIRD_PARTY_LICENSES/CC0-1.0.txt`

## Music — Kevin MacLeod (CC BY 4.0)

The following two works are redistributed under the Creative Commons Attribution 4.0 International license. License legal code: `THIRD_PARTY_LICENSES/CC-BY-4.0.txt` and https://creativecommons.org/licenses/by/4.0/

### Hypnothis

- **Title:** Hypnothis
- **Creator:** Kevin MacLeod
- **Source:** https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100634
- **ISRC:** USUAN1100634
- **License:** CC BY 4.0 — https://creativecommons.org/licenses/by/4.0/
- **File in NotLight:** `assets/audio/background/Hypnothis.mp3`
- **Changes:** no intentional creative modification is documented by the project; if a future release trims, normalizes, loops, remixes or otherwise modifies the work, this line must be updated to describe the change.

Suggested attribution: “Hypnothis” by Kevin MacLeod (incompetech.com), licensed under CC BY 4.0.

### Night Cave

- **Title:** Night Cave
- **Creator:** Kevin MacLeod
- **Source:** https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100446
- **ISRC:** USUAN1100446
- **License:** CC BY 4.0 — https://creativecommons.org/licenses/by/4.0/
- **File in NotLight:** `assets/audio/background/Night_20Cave.mp3`
- **Changes:** no intentional creative modification is documented by the project; if a future release trims, normalizes, loops, remixes or otherwise modifies the work, this line must be updated to describe the change.

Suggested attribution: “Night Cave” by Kevin MacLeod (incompetech.com), licensed under CC BY 4.0.
