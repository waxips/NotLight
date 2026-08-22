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
    "addons/ffmpeg/win64",
    "addons/ffmpeg/linux64",
    "tools/ffmpeg/windows",
    "tools/poppler/windows",
    "tools/typst/windows",
)
FORBIDDEN_NAMES = {
    "ffmpeg.exe", "ffprobe.exe", "pdfinfo.exe", "pdftoppm.exe", "poppler.dll",
    "avcodec-60.dll", "avfilter-9.dll", "avformat-60.dll", "avutil-58.dll",
    "swresample-4.dll", "swscale-7.dll",
    "libgdffmpeg.windows.template_debug.x86_64.dll",
    "libgdffmpeg.windows.template_release.x86_64.dll",
}


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_windows_bootstrap_release.py PACKAGE_DIR", file=sys.stderr)
        return 2
    root = Path(sys.argv[1]).resolve()
    errors: list[str] = []
    if not root.is_dir():
        print(f"ERROR: package directory does not exist: {root}", file=sys.stderr)
        return 2

    for rel in REQUIRED:
        if not (root / rel).is_file():
            errors.append(f"missing required release file: {rel}")
    for rel in FORBIDDEN_DIRS:
        if (root / rel).exists():
            errors.append(f"download-at-first-run runtime leaked into public ZIP: {rel}")
    for p in root.rglob("*"):
        if p.is_file() and p.name.lower() in FORBIDDEN_NAMES:
            errors.append(f"forbidden downloaded runtime binary in public ZIP: {p.relative_to(root).as_posix()}")

    # qpdf is intentionally distributed under Apache-2.0, but copied MSVC
    # runtime DLLs from the upstream qpdf ZIP must not leak into this package.
    qpdf_bin = root / "tools/qpdf/windows/bin"
    if qpdf_bin.is_dir():
        allowed = {"qpdf.exe", "qpdf30.dll"}
        extras = sorted(p.name for p in qpdf_bin.iterdir() if p.is_file() and p.name not in allowed)
        if extras:
            errors.append("unexpected qpdf runtime files: " + ", ".join(extras))

    manifest = root / "NOTLIGHT_RELEASE_MANIFEST.json"
    if manifest.is_file():
        try:
            data = json.loads(manifest.read_text(encoding="utf-8-sig"))
            if data.get("schema") != "notlight.public-windows-bootstrap":
                errors.append("invalid public release manifest schema")
        except Exception as exc:
            errors.append(f"invalid NOTLIGHT_RELEASE_MANIFEST.json: {exc}")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print(f"Windows bootstrap release validation failed: {len(errors)} error(s).", file=sys.stderr)
        return 1
    print("Windows bootstrap release validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
