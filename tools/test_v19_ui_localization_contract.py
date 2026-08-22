# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_settings_option_buttons_do_not_resize_modal_from_long_items() -> None:
    text = (ROOT / "scripts/ui/settings_dialog.gd").read_text(encoding="utf-8")
    assert "option.fit_to_longest_item = false" in text
    assert "option.size_flags_vertical = Control.SIZE_SHRINK_CENTER" in text
    assert "option.custom_minimum_size = Vector2(190.0, 38.0)" in text


def test_ambient_phrases_are_centralized_in_russian_catalog() -> None:
    layer = (ROOT / "scripts/ui/hub_ambient_phrase_layer.gd").read_text(encoding="utf-8")
    assert "PHRASE_KEYS" in layer
    assert "NotLightL10n.text(key)" in layer
    # The runtime resolves ambient phrases through the canonical localization
    # catalog. phrases.json is intentionally retained as a CC0 author/reference
    # catalog and is not loaded by HubAmbientPhraseLayer.
    phrase_catalog = ROOT / "localization/ambient/phrases.json"
    assert phrase_catalog.is_file()
    reference = json.loads(phrase_catalog.read_text(encoding="utf-8"))
    assert reference.get("license") == "CC0-1.0"
    data = json.loads((ROOT / "localization/core/ru.json").read_text(encoding="utf-8"))
    strings = data["strings"]
    phrases = [value for key, value in strings.items() if key.startswith("ambient.phrase.")]
    assert len(phrases) >= 40
    assert all(str(value).strip() for value in phrases)


def test_core_russian_baseline_is_canonical_with_retained_locales() -> None:
    core = ROOT / "localization/core"
    assert sorted(path.name for path in core.glob("*.json")) == ["be.json", "en.json", "ru.json", "uk.json"]
    data = json.loads((core / "ru.json").read_text(encoding="utf-8"))
    assert len(data["strings"]) >= 2000
    # Other locale bundles are intentionally retained as translation work-in-progress;
    # Russian alone is the completeness authority for newly centralized UI keys.
    for locale in ("be", "en", "uk"):
        optional = json.loads((core / f"{locale}.json").read_text(encoding="utf-8"))
        assert isinstance(optional.get("strings"), dict)
        assert optional["strings"]


def test_shortcut_and_in_app_brand_marks_are_separate_triads() -> None:
    shortcut = (ROOT / "icon.svg").read_text(encoding="utf-8")
    assert 'fill="#000000"' in shortcut
    assert shortcut.count('fill="#ffffff"') == 3

    internal = (ROOT / "assets/brand/notlight_internal_triad.svg").read_text(encoding="utf-8")
    internal_lower = internal.lower()
    assert 'fill="#237f52"' in internal_lower
    assert 'fill="#faf8eb"' in internal_lower
    assert 'fill="#bce3c9"' in internal_lower
    assert internal_lower.count('<ellipse') >= 4

    hub = (ROOT / "scripts/ui/hub_screen.gd").read_text(encoding="utf-8")
    about = (ROOT / "scripts/ui/project_about_dialog.gd").read_text(encoding="utf-8")
    brand_path = 'res://assets/brand/notlight_internal_triad.svg'
    assert brand_path in hub
    assert brand_path in about
