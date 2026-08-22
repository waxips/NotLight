<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Publishing the NotLight source code to GitHub

This document covers **source-code publication only**. It does not require you to publish a Windows binary release.

The existing repository is:

`https://github.com/waxips/NotLight`

It may already contain a placeholder `README.md` and `LICENSE`. The safest workflow is to clone that repository first and then copy the prepared NotLight source tree into the clone.

## What belongs in the source repository?

Yes, `tools/` belongs in GitHub. It contains source-controlled tests, validation scripts, build/setup scripts, and dependency provenance records.

The source repository should also contain `.github/`, `THIRD_PARTY_LICENSES/`, the license/notices files, the Godot project files, source code, assets, localization, and documentation.

The repository must **not** contain generated caches/build output or downloaded runtime binaries such as:

```text
.godot/
.pytest_cache/
__pycache__/
dist/
build_wow/
addons/ffmpeg/win64/
addons/ffmpeg/linux64/
tools/ffmpeg/windows/bin/ffmpeg.exe
tools/ffmpeg/windows/bin/ffprobe.exe
tools/poppler/windows/
tools/typst/windows/typst.exe
```

Those paths are intentionally covered by `.gitignore`.

## Safe first push into the existing repository

1. Create or open a parent folder where you want the GitHub checkout to live.
2. Clone the existing repository:

```bash
git clone https://github.com/waxips/NotLight.git
cd NotLight
```

3. Copy **the contents** of the prepared source archive's `NotLight/` folder into this cloned `NotLight` folder.
4. Replace the placeholder `README.md` and `LICENSE` when asked.
5. Do **not** delete or replace the `.git/` folder created by `git clone`.
6. Review the changes:

```bash
git status
```

7. Stage the source tree:

```bash
git add -A
git status
```

8. Confirm that the generated/runtime paths listed above are not staged.
9. Commit:

```bash
git commit -m "Publish NotLight source code"
```

10. Push the current branch:

```bash
git push origin HEAD
```

## After the push

Open `https://github.com/waxips/NotLight` and verify that the repository root shows:

- `README.md` with the title **NotLight**;
- `LICENSE`;
- `COPYRIGHT`;
- `THIRD_PARTY_NOTICES.md`;
- `THIRD_PARTY_COMPONENTS.json`;
- `CORRESPONDING_SOURCE.md`;
- `RELEASE_COMPLIANCE.md`;
- `project.godot`;
- `.github/`;
- `tools/`;
- the source, assets, localization, and documentation directories.

That completes publication of the **source code**. A downloadable Windows release is a separate process and can be handled later.
