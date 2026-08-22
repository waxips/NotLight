#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Validate the user-facing Windows bootstrap package before publication."""
from __future__ import annotations

import json
from pathlib import Path
import sys

REQUIRED = (
    "NotLight.exe",
    "NotLight.pck",
    "00_START_HERE.txt",
    "START_NOTLIGHT.bat",
    "SETUP_WINDOWS_DEPENDENCIES.ps1",
    "README_WINDOWS.txt",
    "SOURCE_CODE.txt",
    "LICENSE",
    "COPYRIGHT",
    "THIRD_PARTY_NOTICES.md",
    "CORRESPONDING_SOURCE.md",
    "THIRD_PARTY_COMPONENTS.json",
    "THIRD_PARTY_LICENSES/Godot-MIT.txt",
    "THIRD_PARTY_LICENSES/GODOT_COPYRIGHT.txt",
    "THIRD_PARTY_LICENSES/QPDF-Apache-2.0.txt",
    "THIRD_PARTY_LICENSES/QPDF-NOTICE.md",
    "THIRD_PARTY_LICENSES/Typst-Apache-2.0.txt",
    "THIRD_PARTY_LICENSES/Typst-NOTICE.txt",
    "THIRD_PARTY_LICENSES/MiTeX-Apache-2.0.txt",
    "THIRD_PARTY_LICENSES/CC-BY-4.0.txt",
    "THIRD_PARTY_LICENSES/CC0-1.0.txt",
    "NOTLIGHT_RELEASE_MANIFEST.json",
)

FORBIDDEN_DIRS = (
    ".godot",
    ".git",
    "dist",
    "addons/ffmpeg/win64",
    "addons/ffmpeg/linux64",
    "tools/ffmpeg/windows",
    "tools/poppler/windows",
    "tools/typst/windows",
)

FORBIDDEN_NAMES = {
    "ffmpeg.exe",
    "ffprobe.exe",
    "pdfinfo.exe",
    "pdftoppm.exe",
    "poppler.dll",
    "typst.exe",
    "avcodec-60.dll",
    "avfilter-9.dll",
    "avformat-60.dll",
    "avutil-58.dll",
    "swresample-4.dll",
    "swscale-7.dll",
    "libgdffmpeg.windows.template_debug.x86_64.dll",
    "libgdffmpeg.windows.template_release.x86_64.dll",
}

EIRTEAM_ROOT_FILES = (
    "libgdffmpeg.windows.template_release.x86_64.dll",
    "avcodec-60.dll",
    "avfilter-9.dll",
    "avformat-60.dll",
    "avutil-58.dll",
    "swresample-4.dll",
    "swscale-7.dll",
)

FFMPEG_MIRROR = (
    "https://github.com/GyanD/codexffmpeg/releases/download/"
    "8.1.2/ffmpeg-8.1.2-essentials_build.zip"
)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_windows_bootstrap_release.py PACKAGE_DIR", file=sys.stderr)
        return 2

    root = Path(sys.argv[1]).resolve()
    if not root.is_dir():
        print(f"ERROR: package directory does not exist: {root}", file=sys.stderr)
        return 2

    errors: list[str] = []

    for rel in REQUIRED:
        if not (root / rel).is_file():
            errors.append(f"missing required release file: {rel}")

    for rel in FORBIDDEN_DIRS:
        if (root / rel).exists():
            errors.append(f"forbidden generated/download-at-first-run path in public ZIP: {rel}")

    for path in root.rglob("*"):
        if path.is_file() and path.name.lower() in FORBIDDEN_NAMES:
            errors.append(
                "forbidden downloaded runtime binary in public ZIP: "
                + path.relative_to(root).as_posix()
            )

    if (root / "NotLightBoard.exe").exists() or (root / "NotLightBoard.pck").exists():
        errors.append("legacy NotLightBoard application artifact is present")

    start_bat = root / "START_NOTLIGHT.bat"
    if start_bat.is_file():
        text = start_bat.read_text(encoding="utf-8-sig", errors="replace")
        if "NotLight.exe" not in text:
            errors.append("START_NOTLIGHT.bat does not launch NotLight.exe")
        if "SETUP_WINDOWS_DEPENDENCIES.ps1" not in text:
            errors.append("START_NOTLIGHT.bat does not invoke first-run dependency setup")

    setup_script = root / "SETUP_WINDOWS_DEPENDENCIES.ps1"
    if setup_script.is_file():
        text = setup_script.read_text(encoding="utf-8-sig", errors="replace")
        for name in EIRTEAM_ROOT_FILES:
            if name not in text:
                errors.append(
                    "first-run setup does not restore required root-level "
                    f"EIRTeam runtime: {name}"
                )
        if FFMPEG_MIRROR not in text:
            errors.append("first-run setup does not use the pinned FFmpeg GitHub mirror")

    # qpdf is intentionally distributed under Apache-2.0. Only the audited pair
    # is allowed in the public qpdf runtime directory.
    qpdf_bin = root / "tools/qpdf/windows/bin"
    if not qpdf_bin.is_dir():
        errors.append("bundled qpdf runtime directory is missing")
    else:
        allowed = {"qpdf.exe", "qpdf30.dll"}
        names = {p.name for p in qpdf_bin.iterdir() if p.is_file()}
        missing = sorted(allowed - names)
        extras = sorted(names - allowed)
        if missing:
            errors.append("missing qpdf runtime files: " + ", ".join(missing))
        if extras:
            errors.append("unexpected qpdf runtime files: " + ", ".join(extras))

    manifest = root / "NOTLIGHT_RELEASE_MANIFEST.json"
    if manifest.is_file():
        try:
            data = json.loads(manifest.read_text(encoding="utf-8-sig"))
            if data.get("schema") != "notlight.public-windows-bootstrap":
                errors.append("invalid public release manifest schema")
            if data.get("application") != "NotLight.exe":
                errors.append("public release manifest application must be NotLight.exe")
            if data.get("starter") != "START_NOTLIGHT.bat":
                errors.append("public release manifest starter must be START_NOTLIGHT.bat")
        except Exception as exc:
            errors.append(f"invalid NOTLIGHT_RELEASE_MANIFEST.json: {exc}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(
            f"Windows bootstrap release validation failed: {len(errors)} error(s).",
            file=sys.stderr,
        )
        return 1

    print("Windows bootstrap release validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
