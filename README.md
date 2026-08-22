<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# NotLight

**NotLight** is a local-first workspace for visual boards, notes, study material, reusable resources, and extensible modules. It is designed especially for students, teachers, and anyone who prefers arranging information on a free-form canvas instead of forcing everything into a linear document.

> **Project status:** active development. This repository publishes the **NotLight source code**. Windows builds are handled separately through the release workflow and may not be available for every source revision. File formats, module APIs, and some workflows may still evolve between releases.

## Highlights

- **Visual boards** — place text, cards, images, media, drawings, and other objects on a large free-form workspace.
- **Notes** — create formatted notes with a source/editing workflow and rendered preview.
- **Resource Library** — import local files once and reuse them across boards.
- **PDF, image, video, and audio support** — local preview and processing through bundled or replaceable desktop runtimes.
- **Voice notes** — microphone recording starts only after an explicit user action.
- **Math formulas** — rendered locally through Typst and the MiTeX package.
- **Portable packages** — export and import boards, libraries, and modules using NotLight container formats.
- **Modules** — an extensible module system with manifests and file-integrity checks.
- **Localization** — Russian, English, Ukrainian, and Belarusian UI resources are included.
- **Local-first architecture** — the main project data and media workflows are designed to work without an account or cloud backend.

## Portable formats

NotLight uses manifest-based portable containers with SHA-256 validation.

| Data | Extension |
| --- | --- |
| Board | `.notlight-board` |
| Resource library | `.notlight-library` |
| Module | `.notlight-module` |

Imported packages should be treated as untrusted input. The project validates container structure, paths, size limits, and SHA-256 values before materializing payload files.

## Windows builds

### Quick start

When a Windows build is published, students, teachers, and other end users do not need the development setup described below.

1. Download the Windows ZIP from the project's GitHub Releases page or the official project channel.
2. Extract the **entire ZIP** into a normal folder.
3. Double-click **`START_NOTLIGHT.bat`**.
4. The first start downloads the pinned media/PDF/formula runtime components directly from their upstream providers and verifies the downloaded archives before installation. An Internet connection is required for this one-time setup.
5. After setup, NotLight starts automatically. Later launches reuse the installed runtime files.

The public NotLight ZIP intentionally does not redistribute several large third-party GPL/LGPL runtime binaries. This makes the public package simpler to audit and keeps those binaries coming directly from their upstream providers. The ZIP includes `README_WINDOWS.txt` with the same instructions in English and Russian.

Do **not** run the application from inside the ZIP and do not move only `NotLight.exe`; keep the extracted folder together.

### Windows requirements

- Windows 10 or Windows 11, x64;
- Internet access for the first-run dependency setup;
- the supported Microsoft Visual C++ Redistributable x64 (v14 runtime) for the included qpdf sidecar on systems where that runtime is not already installed;
- a microphone only if you want to record voice notes.

The build is currently not code-signed, so Windows SmartScreen may warn about a newly downloaded build. Official releases include `SHA256SUMS.txt`; verify the archive against it when possible.

## Data storage

Application data is stored below Godot's `user://notlight` directory. The logical layout includes:

```text
user://notlight/boards
user://notlight/library
user://notlight/modules
```

The physical location of `user://` depends on the operating system and Godot configuration. Avoid editing internal storage files while NotLight is running. Use the built-in export/import workflows when moving data between installations.

## Repository layout

```text
addons/                  GDExtensions and export integration
assets/                  icons, shaders, branding, and licensed media
localization/            UI localization resources
scenes/                  Godot scenes
scripts/                 application code
  app/                    application composition
  assets/                 Resource Library and import logic
  board/                  board model and behavior
  media/                  PDF, video, audio, and recording
  modules/                module system
  notes/                  notes and preview
  portable/               portable package formats
  render/                 board rendering
  settings/               settings and persistence
  ui/                     UI, dialogs, and theme
sdk/                      module API material
tools/                    pinned runtimes, checks, and build scripts
THIRD_PARTY_LICENSES/     third-party license and notice copies
```

`.godot/` is generated editor/import cache. It is not source material and must not be committed or included in source-release archives.

## Documentation

Current maintained architecture and release documents include:

- [`docs/AUDIO_MASTER_AND_BACKGROUND_MUSIC.md`](docs/AUDIO_MASTER_AND_BACKGROUND_MUSIC.md) — application audio, bundled/Library background music, and ducking;
- [`docs/PDF_SUPPORT.md`](docs/PDF_SUPPORT.md) — PDF import, Poppler rendering, qpdf durable variants, and release boundaries;
- [`docs/MODULE_API_V1.md`](docs/MODULE_API_V1.md) — executable Module API v1 contract and trust model;
- [`docs/MANUAL_TEST_CHECKLIST.md`](docs/MANUAL_TEST_CHECKLIST.md) — release-candidate manual checks;
- [`docs/GITHUB_PUBLISHING.md`](docs/GITHUB_PUBLISHING.md) — first-push and source-repository publishing workflow;
- [`RELEASE_COMPLIANCE.md`](RELEASE_COMPLIANCE.md) — redistribution/compliance publish gate.

## Development

### Main stack

- **Godot Engine 4.4.1**;
- GDScript;
- EIRTeam.FFmpeg GDExtension for FFmpeg-backed video integration;
- FFmpeg/ffprobe sidecars for media processing;
- Poppler tools for PDF metadata/rasterization;
- qpdf for optional PDF optimization;
- Typst + MiTeX for local formula rendering.

### Open the project

1. Install **Godot 4.4.1**.
2. Clone the repository.
3. On Windows, restore the pinned downloaded runtimes:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tools\setup_windows_dependencies.ps1
   ```

4. Open `project.godot` in Godot.
5. Run the main scene from the editor.

The public source repository intentionally does **not** commit the downloaded
EIRTeam.FFmpeg runtime DLL/SO files, Gyan FFmpeg CLI executables, Poppler Windows
runtime, or the large Typst Windows executable. The setup script downloads exact
pinned upstream archives, verifies their SHA-256 values, and restores the local
working runtime. This keeps the Git repository source-focused and avoids making
the normal source checkout a redistribution point for copied GPL/LGPL object
code.

The small qpdf runtime and MiTeX local package remain in the repository with
their Apache-2.0 licenses/notices and provenance. See the component `SOURCE_INFO.md`
files before changing any dependency version.

## Windows release build

Normal releases are built by **GitHub Actions** from an exact Git tag. This is the recommended path because it runs the tests, restores pinned dependencies, verifies the official Godot editor/templates, smoke-tests the full local export, removes downloaded third-party runtimes from the public package, validates the final ZIP, and publishes `SHA256SUMS.txt`.

To test the pipeline without publishing a release, open the repository's **Actions → Build Windows release → Run workflow**. The resulting ZIP appears as a workflow artifact.

To publish a version, tag the exact commit, for example:

```bash
git tag -a v0.1.0 -m "NotLight v0.1.0"
git push origin v0.1.0
```

The workflow creates a GitHub Release and attaches a file named like:

```text
NotLight-v0.1.0-windows-x86_64.zip
SHA256SUMS.txt
```

That same Windows ZIP is the file intended for redistribution through the official Telegram channel. End users only need to extract it and double-click `START_NOTLIGHT.bat`. The package also places `00_START_HERE.txt` at the top level with a three-step English/Russian quick start intended for non-technical users.

For local developer exports, `tools/build_windows.ps1` still builds and smoke-tests a full runtime-equipped `dist/` directory. That internal `dist/` tree is **not** the public download. `tools/make_windows_bootstrap_release.ps1` turns it into the audited public bootstrap package.

### Static validation

From the repository root:

```bash
python -B -m pytest -q -p no:cacheprovider
python tools/validate_project.py
python tools/validate_release_compliance.py
```

For the public bootstrap ZIP, the important additional gate is:

```bash
python tools/validate_windows_bootstrap_release.py <package-directory>
```

It fails if EIRTeam/FFmpeg CLI/Poppler/Typst downloaded runtime binaries accidentally leak into the public ZIP. Those components are installed on the recipient's machine by the pinned first-run setup instead.

## Third-party runtime provenance

Pinned versions, hashes, and refresh/build information are documented in:

- `tools/ffmpeg/SOURCE_INFO.md` — FFmpeg/ffprobe CLI build;
- `addons/ffmpeg/SOURCE_INFO.md` — EIRTeam.FFmpeg and its FFmpeg shared libraries;
- `tools/poppler/SOURCE_INFO.md` — Poppler Windows runtime;
- `tools/qpdf/SOURCE_INFO.md` — qpdf Windows runtime;
- `tools/typst/SOURCE_INFO.md` — Typst and MiTeX;
- `THIRD_PARTY_COMPONENTS.json` — machine-readable component/license inventory.

Do not replace a pinned dependency with a newer binary without updating its hashes, source/provenance information, notices, and release checks.

> **Current redistribution/compliance status:** EIRTeam.FFmpeg provenance is verified against the official **v1.1.4** release asset (`SHA-256 1a8dbc4d7524172ca72517dac4ffb24965025c2f19067882be35376b75bc107c`), and all Windows/Linux runtime binaries used during development match it byte-for-byte. The public source repository does not commit the downloaded EIRTeam/FFmpeg CLI/Poppler/Typst runtime binaries, and the public Windows ZIP does not contain them either: `START_NOTLIGHT.bat` downloads the pinned upstream packages on the recipient machine. If a future release changes back to directly bundling those object files, the corresponding GPL/LGPL source-delivery review must be reopened.

## Licensing

### NotLight source code

Unless a file says otherwise, NotLight's original source code is distributed under the **GNU General Public License v3.0 or later (`GPL-3.0-or-later`)**.

- Full license text: [`LICENSE`](LICENSE)
- Copyright statement: [`COPYRIGHT`](COPYRIGHT)

Third-party software and assets retain their own licenses. Their presence in this repository does not relicense them as GPL.

### Third-party notices

The primary legal/compliance files are:

- [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) — human-readable component and attribution notices;
- [`THIRD_PARTY_LICENSES/`](THIRD_PARTY_LICENSES/) — retained license/NOTICE texts;
- [`THIRD_PARTY_COMPONENTS.json`](THIRD_PARTY_COMPONENTS.json) — machine-readable inventory;
- [`CORRESPONDING_SOURCE.md`](CORRESPONDING_SOURCE.md) — source/build-provenance map for redistributed binaries;
- [`RELEASE_COMPLIANCE.md`](RELEASE_COMPLIANCE.md) — release checklist and blocking conditions.

A binary release should not be published merely because these files exist. GPL/LGPL-covered object code must have the matching source/build material made available using a compliant distribution method. `RELEASE_COMPLIANCE.md` treats unresolved provenance as a release blocker rather than silently assuming compliance.

### Music

NotLight currently redistributes two Kevin MacLeod tracks under **Creative Commons Attribution 4.0 International (CC BY 4.0)**:

- **Hypnothis** — Kevin MacLeod, ISRC `USUAN1100634`;
- **Night Cave** — Kevin MacLeod, ISRC `USUAN1100446`.

The work URLs, license URL, attribution, and change-status statements are recorded in `THIRD_PARTY_NOTICES.md`; the CC BY 4.0 legal code is retained in `THIRD_PARTY_LICENSES/CC-BY-4.0.txt`.

## Corresponding source for binary releases

For downloadable releases, publish source material alongside the binary release and keep clear directions next to the binary download. At minimum, the release process must cover:

- the exact NotLight source revision used to build the release;
- the exact source/build material required for GPL/LGPL-covered redistributed binaries;
- any dependency source or relink material required by those licenses;
- retained license and attribution notices.

The concrete release-time checklist is in [`RELEASE_COMPLIANCE.md`](RELEASE_COMPLIANCE.md).

## Source archive integrity

`FILE_CHECKSUMS.sha256` is generated from the clean source-release tree. It intentionally excludes generated/cache/build directories such as `.godot/`, `.pytest_cache/`, `__pycache__/`, and `dist/`, as well as the checksum file itself.

Regenerate after release-source changes:

```bash
python tools/generate_file_checksums.py
```

On systems with GNU `sha256sum`, verify with:

```bash
sha256sum -c FILE_CHECKSUMS.sha256
```

## Security and bug reports

When reporting a bug, include the NotLight build/revision, operating-system version, steps to reproduce, and a minimal example if possible. Do not attach personal documents or other sensitive material unless it is necessary and you are comfortable sharing it.

Repository: https://github.com/waxips/NotLight  
Email: `notlight.official@gmail.com`

## AI-assisted development note

A significant portion of the implementation has been developed with AI-assisted coding under human architectural direction, task definition, and review. That does not change the licensing requirements of NotLight or of any third-party software, binary, music, font, image, or other asset included with it.

## No warranty

NotLight is provided under the warranty disclaimer contained in the GNU GPL. The project is still young and should be treated accordingly: keep backups of important work and test new releases before relying on them for irreplaceable data.
