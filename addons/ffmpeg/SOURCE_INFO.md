<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# EIRTeam.FFmpeg / bundled FFmpeg provenance

This file records the provenance of the EIRTeam.FFmpeg runtime used by NotLight.
The release bundle was re-verified against the official upstream **v1.1.4** asset
on 2026-08-22.

## EIRTeam.FFmpeg wrapper

- Upstream: https://github.com/EIRTeam/EIRTeam.FFmpeg
- Upstream release name: **v1.1.4**
- Release tag: `autobuild-2025-11-12-13-44`
- Upstream commit: `270e661`
- Official release asset: `eirteam-ffmpeg-1.1.4.zip`
- Official release page: https://github.com/EIRTeam/EIRTeam.FFmpeg/releases/tag/autobuild-2025-11-12-13-44
- Verified release-asset SHA-256:
  `1a8dbc4d7524172ca72517dac4ffb24965025c2f19067882be35376b75bc107c`
- Wrapper license: MIT (`THIRD_PARTY_LICENSES/EIRTeam.FFmpeg-MIT.txt`)

### Byte-for-byte verification

The Windows and Linux runtime binaries currently used by NotLight were compared
with the files from the official `eirteam-ffmpeg-1.1.4.zip` asset. **All 16
runtime binaries match byte-for-byte.**

Windows:

```text
be1909c25afc88c6b54daa1372ef9fe402518b4459a6f09bf513c17b062c6f46  win64/avcodec-60.dll
5bd684f98cfe0f0d9adf410ffa8a97efbdd0ebd6b830ffb2561d5dd337b8bc33  win64/avfilter-9.dll
be395e0b846690841c152c019d746207af9b595bdbd0ae5dba55ce1e1306aa39  win64/avformat-60.dll
e2d6add09e9aa735ce7a9dc3b25cb00151d412556b1a1da0dea1a8b597729a98  win64/avutil-58.dll
e0301da2e1f9f1cb1625e6b72f969c253a91c9496f174d664732c35ab3423c36  win64/libgdffmpeg.windows.template_debug.x86_64.dll
958189ecf4c9201d5f1119937fcdc13ee1ed4b4c2271bced5f6f3d55f25a38d3  win64/libgdffmpeg.windows.template_release.x86_64.dll
ef963e60786af7523ef3d83feeee3d11ca45672a58845ad30c11f5573bca8146  win64/swresample-4.dll
81050c2d623c8834d9af9a8cc6244b9e5c6e901e53cd288214178b3447fbee73  win64/swscale-7.dll
```

Linux:

```text
71a6707cdeab94425c8dfaaeae3c97f47c1e38dcea817a196b9f815772d998dc  linux64/libavcodec.so.60
37f6277343e7235398d2b157480ffcb472824fb6a965bb1fee0374194c8db34d  linux64/libavfilter.so.9
a7e451fa96072a702029b380e09e91cd6d4c4deaf9fe52fe308d109b0c367a47  linux64/libavformat.so.60
27e3d406423c5b5308ec3c44410f561f33c7146346dc572ebbe59ab74798c571  linux64/libavutil.so.58
bd3e7e3314e68c8fe2419b6bbe7e637b9ac8f3366640119b6e40658cfac6ce90  linux64/libgdffmpeg.linux.template_debug.x86_64.so
5e4936f58d56f9d491707c41536cc8c04d772b50695790ebd32e4aaa01276efa  linux64/libgdffmpeg.linux.template_release.x86_64.so
a88c56faba2628e977786490cb04b8f9d2a9524cfaede0d3d9abe29951ab7c81  linux64/libswresample.so.4
92bf879222de54bf063ba8668aad7c8795617f5debb4a985567817542508734b  linux64/libswscale.so.7
```

The local `ffmpeg.gdextension` file is intentionally not byte-identical to the
upstream asset. NotLight removes the Android and macOS library/dependency entries
because those platform binaries are not shipped in this repository. Its Windows
and Linux paths are otherwise the upstream v1.1.4 paths.

The upstream `.lib` and `.exp` development/linker files are not needed at runtime
and are not included by NotLight.

## FFmpeg libraries inside the official EIRTeam asset

The official v1.1.4 asset contains FFmpeg 6-era shared libraries. The Windows
libraries identify themselves as:

- FFmpeg build id: `N-111611-g5b11ee9429-20230724`
- source commit prefix: `5b11ee9429`
- shared build: `--enable-shared --disable-static`
- version-3 licensing mode: `--enable-version3`
- GPL mode is **not** enabled (`--enable-gpl` is absent)
- nonfree mode is **not** enabled (`--enable-nonfree` is absent)

Accordingly, the FFmpeg library layer identifies as an **LGPLv3-or-later** build,
subject also to the licenses of the external libraries linked into that build.
The retained LGPLv3 text is:

```text
THIRD_PARTY_LICENSES/EIRTeam.FFmpeg-FFmpeg-LGPLv3.txt
```

The embedded configure line enables a number of external libraries. This is why
an eventual NotLight **binary** release must not treat the FFmpeg core source
alone as a complete source/license package without checking the corresponding
build/dependency material.

## Source-repository policy

The public NotLight **source repository does not commit the EIRTeam runtime
DLL/SO files**. `tools/setup_windows_dependencies.ps1` downloads the exact
official v1.1.4 asset above, verifies the archive SHA-256, and restores the
runtime locally. This keeps a normal source-code checkout from redistributing
LGPL-covered FFmpeg object code on NotLight's behalf.

A downloadable NotLight Windows build is different: if the build contains these
DLLs, NotLight is redistributing them and must satisfy the applicable LGPL/source
and notice obligations for that binary release. See `CORRESPONDING_SOURCE.md`
and `RELEASE_COMPLIANCE.md`.

## Replacement/relink policy for binary releases

The FFmpeg libraries must remain separate DLL/SO dependencies rather than being
merged into the NotLight executable. Release packaging must not intentionally
add technical restrictions that prevent an interface-compatible modified
replacement from being used.
