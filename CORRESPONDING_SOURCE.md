<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Source and provenance map

This file explains where the source/provenance for NotLight and its third-party components comes from. It is release-engineering documentation, not legal advice.

## NotLight itself

NotLight's original source code is licensed under **GPL-3.0-or-later** unless a file says otherwise.

Official repository:

https://github.com/waxips/NotLight

For an official release, the exact NotLight source revision is the Git tag matching that release (for example `v0.1.0`).

## Public Windows package model

The recommended public Windows ZIP is a **bootstrap package**. It contains the NotLight/Godot application, legal notices, the small Apache-licensed qpdf runtime, the Apache-licensed MiTeX package, and first-run setup files.

It intentionally does **not** contain these downloaded runtime object files:

- EIRTeam.FFmpeg / FFmpeg DLLs;
- Gyan.dev `ffmpeg.exe` / `ffprobe.exe`;
- Poppler Windows runtime;
- Typst Windows executable.

`START_NOTLIGHT.bat` invokes `SETUP_WINDOWS_DEPENDENCIES.ps1`, which downloads the exact pinned archives directly from the upstream providers on the recipient machine and verifies their SHA-256 values before installation.

This avoids using the public NotLight ZIP itself as a redistribution point for those downloaded GPL/LGPL runtime binaries. If a future release directly bundles any of them, the corresponding source-delivery obligations for that directly redistributed object code must be reviewed again before publication.

## EIRTeam.FFmpeg v1.1.4

- Upstream: https://github.com/EIRTeam/EIRTeam.FFmpeg
- Release tag: `autobuild-2025-11-12-13-44`
- Commit: `270e661`
- Asset: `eirteam-ffmpeg-1.1.4.zip`
- Asset SHA-256: `1a8dbc4d7524172ca72517dac4ffb24965025c2f19067882be35376b75bc107c`
- Wrapper license: MIT
- FFmpeg shared-library layer: LGPLv3-or-later build as recorded in `addons/ffmpeg/SOURCE_INFO.md`

The Windows/Linux runtime files previously present in the working project were compared with the official v1.1.4 asset; all 16 runtime binaries matched byte-for-byte. The public source repository and public Windows ZIP omit those runtime binaries and retain only the configuration/provenance needed to restore them.

## FFmpeg CLI 8.1.2 Essentials

- FFmpeg upstream: https://ffmpeg.org/
- Provider: https://www.gyan.dev/ffmpeg/builds/
- Provider archive: `ffmpeg-8.1.2-essentials_build.zip`
- Archive SHA-256: `db580001caa24ac104c8cb856cd113a87b0a443f7bdf47d8c12b1d740584a2ec`
- Provider-recorded FFmpeg source commit: `d32b387f2b`
- Provider build/license mode: static GPLv3
- Detailed provenance: `tools/ffmpeg/SOURCE_INFO.md`

The public NotLight ZIP does not contain `ffmpeg.exe` or `ffprobe.exe`; first-run setup downloads the pinned provider archive directly on the recipient machine.

## Poppler 26.02.0 Windows runtime

- Poppler upstream: https://poppler.freedesktop.org/
- Windows provider: https://github.com/oschwartz10612/poppler-windows
- Provider release: `v26.02.0-0`
- Provider archive: `Release-26.02.0-0.zip`
- Archive SHA-256: `993e4a94376ed712fafc7058d724ea0b943d118bbd2305cd9ed55174eb85cda5`
- Poppler license: GPL-2.0-or-later
- Detailed provenance/dependency closure: `tools/poppler/SOURCE_INFO.md`

The public NotLight ZIP does not contain the Poppler runtime. First-run setup downloads the pinned provider archive and retains only the audited files needed by NotLight.

## qpdf 12.4.0

- Upstream: https://github.com/qpdf/qpdf
- Release: `v12.4.0`
- Artifact: `qpdf-12.4.0-msvc64.zip`
- Artifact SHA-256: `5bcb25353f7e6df92b5625dbcfe52a5c34a2a5fba2d1a8b98b8a6a0972c3ff72`
- License: Apache-2.0
- Provenance: `tools/qpdf/SOURCE_INFO.md`

NotLight retains only `qpdf.exe` and `qpdf30.dll`. Apache-2.0 license/NOTICE material is included. Copies of Microsoft VC runtime DLLs from the upstream qpdf archive are intentionally not included.

## Typst 0.15.1 and MiTeX 0.2.7

- Typst upstream: https://github.com/typst/typst
- Typst archive: `typst-x86_64-pc-windows-msvc.zip`
- Typst archive SHA-256: `19ce3551153c2fe7ee9fa2f95208310c8f4d3209fedb699e0333faf8913f6736`
- Typst license: Apache-2.0
- MiTeX upstream: https://github.com/mitex-rs/mitex
- MiTeX version: `0.2.7`
- MiTeX license: Apache-2.0
- Detailed provenance: `tools/typst/SOURCE_INFO.md`

The public NotLight ZIP omits `typst.exe` and downloads it during first-run setup. The local MiTeX package is included with its license/provenance.

## Godot Engine 4.4.1

Godot is MIT-licensed. The release package keeps:

- `THIRD_PARTY_LICENSES/Godot-MIT.txt`;
- `THIRD_PARTY_LICENSES/GODOT_COPYRIGHT.txt`.

The second file is the matching Godot third-party copyright/license inventory retained for the engine/export-template line.

## Creative assets

- Kevin MacLeod tracks are documented in `THIRD_PARTY_NOTICES.md` and licensed CC BY 4.0.
- `localization/ambient/phrases.json` is a CC0-1.0 author/reference catalog; its legal code is retained in `THIRD_PARTY_LICENSES/CC0-1.0.txt`.

## If the packaging model changes

The bootstrap model above is deliberate. Do not silently change the release workflow to place EIRTeam/FFmpeg CLI/Poppler/Typst downloaded runtime binaries directly inside the public ZIP. If that happens, re-run a direct-bundling license/source review and provide the exact source/build material required by the applicable licenses before publishing the altered package.
