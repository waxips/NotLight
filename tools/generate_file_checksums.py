#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate the deterministic SHA-256 manifest for a clean NotLight source release."""

from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "FILE_CHECKSUMS.sha256"
EXCLUDED_DIR_NAMES = {".git", ".godot", ".pytest_cache", "__pycache__", "dist", "build_wow", "release_out", ".godot-ci", ".godot-template-unpack"}
EXCLUDED_FILES = {OUTPUT.resolve()}
EXCLUDED_PATH_PREFIXES = (
    Path("addons/ffmpeg/win64"),
    Path("addons/ffmpeg/linux64"),
    Path("tools/ffmpeg/windows"),
    Path("tools/poppler/windows"),
    Path("tools/typst/windows"),
)


def included_files() -> list[Path]:
    result: list[Path] = []
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        if path.resolve() in EXCLUDED_FILES:
            continue
        relative = path.relative_to(ROOT)
        if any(relative == prefix or prefix in relative.parents for prefix in EXCLUDED_PATH_PREFIXES):
            continue
        if any(part in EXCLUDED_DIR_NAMES for part in relative.parts):
            continue
        if path.suffix.lower() in {".pyc", ".tmp", ".bak"}:
            continue
        result.append(path)
    return sorted(result, key=lambda p: p.relative_to(ROOT).as_posix())


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    lines = [f"{sha256(path)}  {path.relative_to(ROOT).as_posix()}" for path in included_files()]
    OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"Wrote {len(lines)} checksums to {OUTPUT}")


if __name__ == "__main__":
    main()
