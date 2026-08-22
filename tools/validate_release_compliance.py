#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Validate structural release/licensing hygiene for the NotLight source tree.

This checker is intentionally conservative. It verifies files and recorded local
identity, but it cannot decide legal compliance or prove that a source download
has been published on a release page.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

REQUIRED_TOP_LEVEL = (
    "LICENSE",
    "COPYRIGHT",
    "README.md",
    "THIRD_PARTY_NOTICES.md",
    "THIRD_PARTY_COMPONENTS.json",
    "CORRESPONDING_SOURCE.md",
    "RELEASE_COMPLIANCE.md",
    "FILE_CHECKSUMS.sha256",
    "tools/setup_windows_dependencies.ps1",
)
REQUIRED_LICENSES = (
    "THIRD_PARTY_LICENSES/Godot-MIT.txt",
    "THIRD_PARTY_LICENSES/GODOT_COPYRIGHT.txt",
    "THIRD_PARTY_LICENSES/EIRTeam.FFmpeg-MIT.txt",
    "THIRD_PARTY_LICENSES/EIRTeam.FFmpeg-FFmpeg-LGPLv3.txt",
    "THIRD_PARTY_LICENSES/FFmpeg-GPLv3.txt",
    "THIRD_PARTY_LICENSES/Poppler-GPL-2.0.txt",
    "THIRD_PARTY_LICENSES/QPDF-Apache-2.0.txt",
    "THIRD_PARTY_LICENSES/QPDF-NOTICE.md",
    "THIRD_PARTY_LICENSES/Typst-Apache-2.0.txt",
    "THIRD_PARTY_LICENSES/Typst-NOTICE.txt",
    "THIRD_PARTY_LICENSES/MiTeX-Apache-2.0.txt",
    "THIRD_PARTY_LICENSES/CC-BY-4.0.txt",
    "THIRD_PARTY_LICENSES/CC0-1.0.txt",
)
FORBIDDEN_DIR_NAMES = {".godot", ".pytest_cache", "__pycache__", "dist", "build_wow"}
FORBIDDEN_MEDIA_FRAGMENTS = ("narvent", "metamorphosis", "babydoll")
AUDIO_SUFFIXES = {".mp3", ".wav", ".ogg", ".flac", ".m4a", ".aac"}
EXPECTED_HASHES: dict[str, str] = {}
DOWNLOADED_RUNTIME_PATHS = set(EXPECTED_HASHES)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--public-release",
        action="store_true",
        help="also fail on inventory items explicitly marked as blockers (legacy direct-bundling mode)",
    )
    args = parser.parse_args()

    errors: list[str] = []
    warnings: list[str] = []

    for rel in (*REQUIRED_TOP_LEVEL, *REQUIRED_LICENSES):
        if not (ROOT / rel).is_file():
            errors.append(f"missing required file: {rel}")

    for path in ROOT.rglob("*"):
        rel = path.relative_to(ROOT)
        if path.is_dir() and path.name in FORBIDDEN_DIR_NAMES:
            errors.append(f"forbidden generated/build directory in source release: {rel.as_posix()}")
        if path.is_file() and any(fragment in path.name.lower() for fragment in FORBIDDEN_MEDIA_FRAGMENTS):
            errors.append(f"forbidden/undocumented historical media filename: {rel.as_posix()}")

    inventory_path = ROOT / "THIRD_PARTY_COMPONENTS.json"
    inventory: dict = {}
    if inventory_path.is_file():
        try:
            inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            errors.append(f"invalid THIRD_PARTY_COMPONENTS.json: {exc}")

    components = inventory.get("components", []) if isinstance(inventory, dict) else []
    if not isinstance(components, list) or not components:
        errors.append("THIRD_PARTY_COMPONENTS.json has no component inventory")
        components = []

    declared_audio: set[str] = set()
    blockers: list[str] = []
    source_delivery_gates: list[str] = []
    for component in components:
        if not isinstance(component, dict):
            errors.append("component inventory contains a non-object entry")
            continue
        component_id = str(component.get("id", "<missing-id>"))
        status = str(component.get("status", ""))
        repository_presence = str(component.get("repository_presence", "committed"))
        downloaded_runtime = repository_presence == "downloaded-runtime"
        if status == "blocker":
            blockers.append(component_id)
        if status == "source-delivery-required":
            source_delivery_gates.append(component_id)
        for rel in component.get("license_files", []):
            if not (ROOT / str(rel)).is_file():
                errors.append(f"{component_id}: declared license file is missing: {rel}")
        provenance = component.get("provenance_file")
        if provenance and not (ROOT / str(provenance)).is_file():
            errors.append(f"{component_id}: declared provenance file is missing: {provenance}")
        for rel in component.get("local_files", []):
            rel_str = str(rel)
            if not (ROOT / rel_str).is_file() and not downloaded_runtime:
                errors.append(f"{component_id}: declared local file is missing: {rel_str}")
            if Path(rel_str).suffix.lower() in AUDIO_SUFFIXES:
                declared_audio.add(Path(rel_str).as_posix())
        declared_hashes = component.get("sha256", {})
        if declared_hashes and not isinstance(declared_hashes, dict):
            errors.append(f"{component_id}: sha256 must be an object mapping paths to digests")
        elif isinstance(declared_hashes, dict):
            for rel, expected in declared_hashes.items():
                rel_str = str(rel)
                expected_str = str(expected).lower()
                path = ROOT / rel_str
                if not path.is_file():
                    if downloaded_runtime:
                        continue
                    errors.append(f"{component_id}: hashed file is missing: {rel_str}")
                    continue
                actual = sha256(path)
                if actual != expected_str:
                    errors.append(
                        f"{component_id}: hash mismatch for {rel_str}: expected {expected_str}, got {actual}"
                    )

    setup_path = ROOT / "tools/setup_windows_dependencies.ps1"
    setup_text = setup_path.read_text(encoding="utf-8") if setup_path.is_file() else ""
    for component in components:
        if not isinstance(component, dict) or component.get("repository_presence") != "downloaded-runtime":
            continue
        component_id = str(component.get("id", "<missing-id>"))
        download_url = str(component.get("download_url", ""))
        archive_sha = str(component.get("upstream_asset_sha256", "")).lower()
        if download_url and download_url not in setup_text and component_id != "poppler":
            errors.append(f"{component_id}: pinned download URL is not present in setup_windows_dependencies.ps1")
        if archive_sha and archive_sha not in setup_text and component_id != "poppler":
            errors.append(f"{component_id}: pinned archive SHA-256 is not present in setup_windows_dependencies.ps1")

    actual_audio = {
        path.relative_to(ROOT).as_posix()
        for path in ROOT.rglob("*")
        if path.is_file() and path.suffix.lower() in AUDIO_SUFFIXES
    }
    undocumented_audio = sorted(actual_audio - declared_audio)
    if undocumented_audio:
        errors.extend(f"audio file is not declared in THIRD_PARTY_COMPONENTS.json: {rel}" for rel in undocumented_audio)

    for rel, expected in EXPECTED_HASHES.items():
        path = ROOT / rel
        if not path.is_file():
            if rel in DOWNLOADED_RUNTIME_PATHS:
                continue
            errors.append(f"pinned binary missing: {rel}")
            continue
        actual = sha256(path)
        if actual != expected:
            errors.append(f"pinned binary hash mismatch: {rel}: expected {expected}, got {actual}")

    qpdf_dir = ROOT / "tools/qpdf/windows/bin"
    if qpdf_dir.is_dir():
        for path in qpdf_dir.iterdir():
            name = path.name.lower()
            if name == "concrt140.dll" or name.startswith("msvcp140") or name.startswith("vcruntime140"):
                errors.append(f"qpdf directory contains a Microsoft VC runtime copy: {path.relative_to(ROOT).as_posix()}")

    if blockers:
        message = "explicit public-release blockers: " + ", ".join(sorted(blockers))
        if args.public_release:
            errors.append(message)
        else:
            warnings.append(message)
    if source_delivery_gates and args.public_release:
        message = "binary-release source delivery still required: " + ", ".join(sorted(source_delivery_gates))
        errors.append(message)

    old_ru = ROOT / "RELEASE_COMPLIANCE_RU.md"
    if old_ru.exists():
        warnings.append("obsolete RELEASE_COMPLIANCE_RU.md still exists; use RELEASE_COMPLIANCE.md")

    for warning in warnings:
        print(f"WARNING: {warning}")
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)

    if errors:
        print(f"Release hygiene check failed: {len(errors)} error(s), {len(warnings)} warning(s).", file=sys.stderr)
        return 1

    print(f"Release hygiene check passed with {len(warnings)} warning(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
