# FFmpeg CLI provenance

NotLight uses `ffmpeg.exe` and `ffprobe.exe` as external command-line tools for media processing and inspection on Windows.

## Pinned provider package

- Provider: Gyan.dev FFmpeg Windows builds
- Variant: **release essentials**, Windows x86_64, static GPLv3 build
- FFmpeg release: **8.1.2**
- Provider package: `ffmpeg-8.1.2-essentials_build.zip`
- Download URL: `https://github.com/GyanD/codexffmpeg/releases/download/8.1.2/ffmpeg-8.1.2-essentials_build.zip`
- Provider package SHA-256: `db580001caa24ac104c8cb856cd113a87b0a443f7bdf47d8c12b1d740584a2ec`
- FFmpeg source release/tag: `n8.1.2` in the upstream FFmpeg repository

Gyan.dev identifies all of its Windows builds as 64-bit static GPLv3 builds. The Essentials variant includes external libraries including libx264 and libx265.

## Distribution model used by NotLight

The public NotLight source repository does **not** commit `ffmpeg.exe` or `ffprobe.exe`.

The public NotLight Windows bootstrap ZIP also does **not** contain these executables. On first launch, `SETUP_WINDOWS_DEPENDENCIES.ps1` downloads the pinned provider ZIP directly to the recipient's computer, verifies the SHA-256 above, and copies only `ffmpeg.exe` and `ffprobe.exe` into the local NotLight runtime directory.

This file documents the dependency and pin; it is not a claim that Gyan.dev or FFmpeg is part of NotLight's original GPL-covered source code.

If a future NotLight distribution directly bundles the Gyan FFmpeg executables, reopen the GPL corresponding-source review before publication.
