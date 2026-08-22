<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Release checklist

This is a practical release-engineering checklist, not legal advice.

The project uses a simple rule: **the public source repository and the public Windows ZIP do not contain the downloaded EIRTeam/FFmpeg CLI/Poppler/Typst runtime binaries.** Those components are installed on the recipient's Windows machine from pinned upstream archives during first launch.

## 1. Source repository — publishable state

The GitHub repository should contain:

- NotLight source code;
- final localization JSON/reference files;
- `tools/` build/test/setup scripts;
- qpdf's audited `qpdf.exe` + `qpdf30.dll` runtime (Apache-2.0);
- the MiTeX package material (Apache-2.0);
- licensed background music and its CC BY attribution;
- `LICENSE`, `COPYRIGHT`, `THIRD_PARTY_NOTICES.md`, `THIRD_PARTY_COMPONENTS.json`, `CORRESPONDING_SOURCE.md` and `THIRD_PARTY_LICENSES/`.

It must not contain generated caches or the downloaded runtime sets ignored by `.gitignore`.

Before pushing:

```bash
python -B -m pytest -q -p no:cacheprovider
python tools/validate_localization.py
python tools/validate_project.py
python tools/validate_release_compliance.py
python tools/generate_file_checksums.py
```

Commit the resulting `FILE_CHECKSUMS.sha256`.

## 2. EIRTeam provenance — resolved

The exact EIRTeam.FFmpeg runtime was verified against the official v1.1.4 release asset:

```text
release tag: autobuild-2025-11-12-13-44
commit:      270e661
asset:       eirteam-ffmpeg-1.1.4.zip
SHA-256:     1a8dbc4d7524172ca72517dac4ffb24965025c2f19067882be35376b75bc107c
```

All 16 Windows/Linux runtime files that were present in the working project matched the official asset byte-for-byte. `addons/ffmpeg/SOURCE_INFO.md` records the details.

## 3. Public Windows ZIP

The release workflow first creates a full local runtime-equipped build and smoke-tests it. That full `dist/` directory is **not uploaded**.

`tools/make_windows_bootstrap_release.ps1` then creates the public package and removes:

```text
addons/ffmpeg/win64/
addons/ffmpeg/linux64/
tools/ffmpeg/windows/
tools/poppler/windows/
tools/typst/windows/
```

The public ZIP contains `START_NOTLIGHT.bat` and `SETUP_WINDOWS_DEPENDENCIES.ps1`. On first start, the setup script downloads and verifies the pinned EIRTeam, FFmpeg CLI, Poppler and Typst archives directly on the recipient machine.

Validate the public package with:

```bash
python tools/validate_windows_bootstrap_release.py <package-directory>
```

The validator fails if the downloaded runtime binaries leak back into the public ZIP.

## 4. What remains directly distributed

### NotLight

GPL-3.0-or-later. Publish the exact source tag corresponding to the release.

### Godot 4.4.1

MIT. Keep `Godot-MIT.txt` and `GODOT_COPYRIGHT.txt` in the Windows package.

### qpdf 12.4.0

Apache-2.0. Keep `QPDF-Apache-2.0.txt` and `QPDF-NOTICE.md`. Only `qpdf.exe` and `qpdf30.dll` are retained; copied Microsoft VC runtime DLLs are excluded.

### MiTeX 0.2.7

Apache-2.0. Keep its license and deterministic package provenance.

### Kevin MacLeod music

CC BY 4.0. Keep title, creator, direct source link, license link, and an accurate change statement in `THIRD_PARTY_NOTICES.md`.

### Ambient phrase reference catalog

CC0-1.0. Keep `THIRD_PARTY_LICENSES/CC0-1.0.txt` with `localization/ambient/phrases.json`.

## 5. Release automation

Recommended release path:

1. Push the clean source tree to GitHub.
2. Run **Actions → Build Windows release → Run workflow** once as a test. This creates an Actions artifact without creating a public release.
3. Download/test that artifact on a real Windows machine.
4. Tag the exact tested commit, for example `v0.1.0`.
5. Push the tag. GitHub Actions builds the same pipeline and creates the GitHub Release automatically.
6. Publish/share the generated `NotLight-<tag>-windows-x86_64.zip` and its `SHA256SUMS.txt`.
7. For Telegram, redistribute **the exact same ZIP** from the GitHub Release rather than making a second custom build.

## 6. End-user launch contract

The Windows package must contain:

```text
NotLight.exe
NotLight.pck
00_START_HERE.txt
START_NOTLIGHT.bat
SETUP_WINDOWS_DEPENDENCIES.ps1
README_WINDOWS.txt
SOURCE_CODE.txt
LICENSE
COPYRIGHT
THIRD_PARTY_NOTICES.md
THIRD_PARTY_LICENSES/
```

User-facing instructions should lead with one action: **extract the ZIP and double-click `START_NOTLIGHT.bat`.** No user should need to understand the `tools/` tree or install FFmpeg/Poppler manually.

## 7. Do not change these things casually

Before changing any pinned dependency version, update its provenance, hash, notices and setup script together.

Do not directly bundle EIRTeam/FFmpeg CLI/Poppler/Typst runtime object files in the public ZIP unless you intentionally reopen the corresponding direct-redistribution license/source review.

Do not publish `.godot/`, `.pytest_cache/`, `__pycache__/`, `dist/`, `build_wow/`, or historical/undocumented media.
