#!/usr/bin/env python3
"""Validate the centralized Russian localization baseline for NotLight.

Russian is the completeness/canonical source for first-party UI copy. Existing
non-Russian bundles are retained as translation work-in-progress and are allowed
to fall back to Russian when a newer key is not translated yet.
"""
from __future__ import annotations

import hashlib
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCALE_DIR = ROOT / "localization" / "core"
REQUIRED = "ru"
TEXT_CALL_RE = re.compile(r'NotLightL10n\.text\(\s*["\']([^"\']+)["\']')
BIND_RE = re.compile(r'NotLightL10n\.bind_(?:text|tooltip|placeholder_text)\([^\n]*?,\s*["\']([^"\']+)["\']')
PLACEHOLDER_RE = re.compile(r'%(?:\d+\$)?[-+#0 ]*(?:\d+|\*)?(?:\.\d+)?[sdif]|\{[A-Za-z_][A-Za-z0-9_]*\}')
CYR_RE = re.compile(r'[А-Яа-яЁёІіЇїЄєЎў]')
STRING_RE = re.compile(r'(["\'])(.*?)(?<!\\)\1')
CYR_TEST_FIXTURE = "MW@#%&ЖШЩЮЫ"
LEGAL_CREDITS_ARTIFACTS = (
    "THIRD_PARTY_LICENSES/",
    "THIRD_PARTY_COMPONENTS.json",
    "THIRD_PARTY_NOTICES.md",
)

# Strings that are visual glyphs, machine identifiers, standard protocol/tool
# names, file/format syntax, numeric presentation templates or unit notation.
TECH_LITERAL_RE = re.compile(
    r'^(?:'
    r''
    r'|[A-Z]|F\d+|Aa|ƒx|EIRTeam\.FFmpeg|PDF|FFmpeg|Poppler|qpdf|Godot|SHA-256'
    r'|[×+−‹›←→▶Ⅱ⌃⌄⛶●◇□▧▤♪✎♡⚙∞•⋯]+(?:\s*\d+)?'
    r'|\d+(?::\d+)*(?:\s*/\s*\d+(?::\d+)*)?'
    r'|v?%[\d.]*[sdif](?:%%)?(?:\s*(?:px|pt|s|B|KB|MB|GB|FPS)|×)?'
    r'|v%s\s*·\s*%s'
    r'|%s\s*·\s*Ctrl/⌘\+S'
    r'|%s(?:\s*(?:/|·|—|=)\s*%s)*(?:\s*·\s*SHA-256\s*%s)?'
    r'|%s\s*\*|#%s(?:\s*·\s*%d|\s*×)?|/%?\s*%d|/\s*\d+'
    r'|%d(?:\s*/\s*%d|\s*×\s*%d|\s*(?:B|px))?'
    r'|%\.\d+f(?:\s*(?:KB|MB|GB|px|s)|×)?'
    r'|%d\s+%s|%\.1f\s+%s|%s\s+%s(?:\s+%s){0,5}'
    r'|\[b\]%s\[/b\]|▶\s*%s|🔒\s*%s'
    r'|\*\.[A-Za-z0-9*._-]+(?:;[^;]*;[A-Za-z0-9+./_-]+)?'
    r'|\\frac\{[A-Za-z+\-*/]+\}\{[A-Za-z+\-*/]+\}'
    r'|[A-Za-z0-9_.:/\\-]+(?:\.[A-Za-z0-9_-]+)*'
    r')$'
)

UI_PROPERTY_RE = re.compile(r'\.(?:text|tooltip_text|placeholder_text|title|dialog_text|ok_button_text|cancel_button_text|suffix|prefix)\s*=')
UI_METHOD_RE = re.compile(r'\.(?:add_item|add_check_item|add_radio_check_item|add_icon_item|set_item_text|set_tab_title|set_tooltip_text)\(')
MESSAGE_SINK_RE = re.compile(r'(?:_result|_failure|_reject|_emit_diagnostics_error|push_error|push_warning|_set_error|_fail)\s*\(')
DRAW_STRING_RE = re.compile(r'\bdraw_string\s*\(')
DICT_MESSAGE_RE = re.compile(r'["\'](?:error|message|technical_detail|description|hint|tooltip|label|title)["\']\s*:')
SCENE_TEXT_RE = re.compile(r'^\s*(?:text|tooltip_text|placeholder_text|title|dialog_text|suffix|prefix)\s*=\s*"(.*)"\s*$')


def first_party_runtime_gd_files() -> list[Path]:
    files = list((ROOT / "scripts").rglob("*.gd"))
    export_addon = ROOT / "addons" / "notlight_export"
    if export_addon.is_dir():
        files.extend(export_addon.rglob("*.gd"))
    return sorted(set(files))


def no_dupes(pairs):
    counts = Counter(k for k, _ in pairs)
    dupes = [k for k, n in counts.items() if n > 1]
    if dupes:
        raise ValueError("duplicate JSON keys: " + ", ".join(sorted(dupes)))
    return dict(pairs)


def load(path: Path) -> dict[str, str]:
    raw = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=no_dupes)
    strings = raw.get("strings", raw)
    if not isinstance(strings, dict):
        raise ValueError("'strings' must be an object")
    result: dict[str, str] = {}
    for key, value in strings.items():
        if str(key).startswith("_"):
            continue
        if not isinstance(value, str) or not str(key).strip():
            raise ValueError(f"invalid translation {key!r}")
        result[str(key)] = value
    return result


def placeholders(value: str) -> list[str]:
    return sorted(PLACEHOLDER_RE.findall(value))


def used_keys() -> set[str]:
    result: set[str] = set()
    for path in first_party_runtime_gd_files():
        text = path.read_text(encoding="utf-8")
        result.update(TEXT_CALL_RE.findall(text))
        result.update(BIND_RE.findall(text))
    return result


def _literal_is_human(literal: str) -> bool:
    value = literal.strip()
    if not value or TECH_LITERAL_RE.fullmatch(value):
        return False
    if value.startswith(("res://", "user://", "uid://", "http://", "https://")):
        return False
    if re.fullmatch(r'#[0-9A-Fa-f]{3,8}', value):
        return False
    if re.fullmatch(r'[A-Za-z0-9_.:/+\\-]+', value):
        return False
    # Human copy has at least one alphabetic token; pure punctuation/formatting
    # is intentionally not localization material.
    return bool(re.search(r'[A-Za-zА-Яа-яЁёІіЇїЄєЎў]', value))


def runtime_hardcode_failures() -> list[str]:
    failures: list[str] = []
    for path in first_party_runtime_gd_files():
        if path.name == "core_ru_fallback.gd":
            continue
        rel = path.relative_to(ROOT)
        lines = path.read_text(encoding="utf-8").splitlines()
        for no, line in enumerate(lines, 1):
            stripped = line.lstrip()
            if stripped.startswith("#"):
                continue
            if CYR_RE.search(line) and CYR_TEST_FIXTURE not in line:
                failures.append(f"{rel}:{no}: Cyrillic runtime literal outside ru.json")
                continue
            # A line already routing its human copy through the service is okay;
            # the remaining literals on it are usually keys, formats or metadata.
            localized_line = "NotLightL10n.text(" in line or "NotLightL10n.bind_" in line
            sink = bool(UI_PROPERTY_RE.search(line) or UI_METHOD_RE.search(line) or DRAW_STRING_RE.search(line) or MESSAGE_SINK_RE.search(line) or DICT_MESSAGE_RE.search(line))
            if not sink or localized_line:
                continue
            for match in STRING_RE.finditer(line):
                literal = match.group(2)
                if _literal_is_human(literal):
                    failures.append(f"{rel}:{no}: hardcoded human-readable sink literal {literal!r}")
        # Multiline FileDialog filter descriptions must also route through l10n.
        text = "\n".join(lines)
        for no, line in enumerate(lines, 1):
            if ".filters" in line and "PackedStringArray" in line and ";" in line and "NotLightL10n.text(" not in line:
                if re.search(r';[^;]*[A-Za-z]{2,}[^;]*;', line):
                    failures.append(f"{rel}:{no}: hardcoded FileDialog filter label")
    return failures


def scene_hardcode_failures() -> list[str]:
    failures: list[str] = []
    for pattern in ("*.tscn", "*.tres"):
        for path in ROOT.rglob(pattern):
            # Ignore bundled third-party resources if they ever appear.
            if any(part in {"tools", "addons"} for part in path.relative_to(ROOT).parts):
                continue
            for no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                match = SCENE_TEXT_RE.match(line)
                if match and _literal_is_human(match.group(1)):
                    failures.append(f"{path.relative_to(ROOT)}:{no}: hardcoded scene/resource UI text")
    return failures


def localized_const_failures() -> list[str]:
    failures: list[str] = []
    for path in first_party_runtime_gd_files():
        if path.name == "core_ru_fallback.gd":
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        for index, line in enumerate(lines):
            if not re.match(r'\s*const\s+', line):
                continue
            chunk = [line]
            balance = sum(line.count(c) for c in "([{") - sum(line.count(c) for c in ")]}")
            cursor = index + 1
            while balance > 0 and cursor < len(lines) and cursor < index + 100:
                chunk.append(lines[cursor])
                balance += sum(lines[cursor].count(c) for c in "([{") - sum(lines[cursor].count(c) for c in ")]}")
                cursor += 1
            if "NotLightL10n." in "\n".join(chunk):
                failures.append(f"{path.relative_to(ROOT)}:{index + 1}: const expression calls NotLightL10n")
    return failures


def main() -> int:
    failures: list[str] = []
    ru_path = LOCALE_DIR / "ru.json"
    try:
        russian = load(ru_path)
    except Exception as exc:
        print(f"Localization validation failed:\n- invalid ru.json: {exc}")
        return 1

    optional_bundles: dict[str, dict[str, str]] = {}
    for locale in ("be", "en", "uk"):
        path = LOCALE_DIR / f"{locale}.json"
        if not path.is_file():
            continue
        try:
            optional_bundles[locale] = load(path)
        except Exception as exc:
            failures.append(f"invalid optional {locale}.json: {exc}")

    for key, value in russian.items():
        if not value.strip() or value.strip() == key:
            failures.append(f"ru key {key} has empty/technical value")

    # Language-picker labels are endonyms: every UI locale must show each
    # language in that language's own canonical name, independent of the current
    # interface locale. This keeps the picker recognizable after switching UI.
    locale_self_names = {
        "ru": "Русский",
        "be": "Беларуская",
        "en": "English",
        "uk": "Українська",
    }
    all_bundles = {"ru": russian, **optional_bundles}
    for viewer_locale, bundle in sorted(all_bundles.items()):
        for target_locale, self_name in locale_self_names.items():
            key = f"locale.name.{target_locale}"
            if bundle.get(key) != self_name:
                failures.append(
                    f"{viewer_locale} {key} must be the target language self-name {self_name!r}"
                )

    # Credits must name the legal artifacts that actually ship next to the app.
    # The trailing slash intentionally disambiguates THIRD_PARTY_LICENSES/ as a
    # directory rather than another documentation file.
    for artifact in LEGAL_CREDITS_ARTIFACTS:
        source_path = ROOT / artifact.rstrip("/")
        if not source_path.exists():
            failures.append(f"Credits legal artifact does not exist: {artifact}")
    for locale, bundle in sorted(all_bundles.items()):
        for key in ("credits.body", "credits.license_note"):
            value = bundle.get(key, "")
            for artifact in LEGAL_CREDITS_ARTIFACTS:
                if artifact not in value:
                    failures.append(f"{locale} {key} does not name release artifact {artifact}")

    referenced = used_keys()
    missing = sorted(referenced - set(russian))
    if missing:
        failures.append("used literal keys missing from ru.json: " + ", ".join(missing[:100]))

    fallback = ROOT / "scripts/localization/core_ru_fallback.gd"
    canonical = json.dumps(russian, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    digest = hashlib.sha256(canonical).hexdigest()
    if not fallback.is_file() or f"# SOURCE_SHA256: {digest}" not in fallback.read_text(encoding="utf-8"):
        failures.append("generated Russian bootstrap fallback is missing or stale")

    # Regression for the exact issue that motivated the Russian-baseline pass:
    # Board tool rail tooltips must be registered bindings, not one-shot text.
    board_text = (ROOT / "scripts/ui/board_screen.gd").read_text(encoding="utf-8")
    for variable, key in (
        ("_hand_button", "runtime.ui.board_screen.267a14d6c5"),
        ("_select_button", "runtime.ui.board_screen.0f60199287"),
        ("_text_button", "runtime.ui.board_screen.987b2bbd42"),
        ("_draw_button", "board.tool.draw"),
        ("_formula_button", "board.tool.formula"),
        ("_image_import_button", "runtime.ui.board_screen.ed8d4172a4"),
        ("_pdf_import_button", "board.tool.pdf_import"),
        ("_video_import_button", "runtime.ui.board_screen.64c9f7c9aa"),
        ("_audio_import_button", "board.tool.audio_import"),
        ("_voice_record_button", "board.tool.voice_record"),
        ("_library_button", "board.library.tooltip"),
        ("_notes_button", "board.notes.tooltip"),
        ("_module_button", "board.modules.tooltip"),
    ):
        expected = f'NotLightL10n.bind_tooltip({variable}, "{key}")'
        if expected not in board_text:
            failures.append(f"board tool rail tooltip is not centrally bound: {variable}")

    text_toolbar = (ROOT / "scripts/ui/text_context_toolbar.gd").read_text(encoding="utf-8")
    connector_toolbar = (ROOT / "scripts/ui/connector_context_toolbar.gd").read_text(encoding="utf-8")
    if "button.tooltip_text = tooltip" in text_toolbar or "button.tooltip_text = tooltip" in connector_toolbar:
        failures.append("context toolbar helper still stores pre-translated tooltip text instead of a localization binding")
    if "NotLightL10n.bind_tooltip(button, tooltip_key)" not in text_toolbar:
        failures.append("text context toolbar helper tooltips are not centrally bound")
    if "NotLightL10n.bind_tooltip(button, tooltip_key)" not in connector_toolbar:
        failures.append("connector context toolbar helper tooltips are not centrally bound")

    runtime_text = (ROOT / "scripts/localization/localization_service.gd").read_text(encoding="utf-8")
    facade_text = (ROOT / "scripts/localization/notlight_l10n.gd").read_text(encoding="utf-8")
    expected_locales = '["ru", "be", "en", "uk"]'
    if f'const SUPPORTED_LOCALES: Array[String] = {expected_locales}' not in runtime_text:
        failures.append("runtime service must retain the shipped ru/be/en/uk locale set")
    if f'const FALLBACK_LOCALES: Array[String] = {expected_locales}' not in facade_text:
        failures.append("localization facade must retain the shipped ru/be/en/uk locale set")
    if "refresh_tree(tree.root)" not in runtime_text:
        failures.append("locale changes do not centrally refresh bound controls")

    failures.extend(runtime_hardcode_failures())
    failures.extend(scene_hardcode_failures())
    failures.extend(localized_const_failures())

    if failures:
        print("Localization validation failed:")
        for failure in failures:
            print("-", failure)
        return 1

    print(f"Localization validation passed: {len(russian)} Russian canonical keys; {len(referenced)} literal keys referenced.")
    print("- Russian canonical completeness baseline: passed")
    if optional_bundles:
        coverage = ", ".join(f"{loc}={len(bundle)}" for loc, bundle in sorted(optional_bundles.items()))
        print(f"- optional retained locale bundles parsed: {coverage}")
    print("- runtime/UI hardcode guard: passed")
    print("- scene/resource hardcode guard: passed")
    print("- board tool-rail tooltip binding regression: passed")
    print("- generated Russian bootstrap fallback: passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
