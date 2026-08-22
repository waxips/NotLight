#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Static contract checks for safe clickable links in the About dialog."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ABOUT = ROOT / "scripts" / "ui" / "project_about_dialog.gd"


def test_about_dialog_linkifies_plain_web_urls() -> None:
    source = ABOUT.read_text(encoding="utf-8")
    assert '_linkify_web_urls(NotLightL10n.text("about.body"))' in source
    assert 'url_pattern.sub(bbcode, "[url=$1]$1[/url]", true)' in source


def test_about_dialog_connects_meta_clicked() -> None:
    source = ABOUT.read_text(encoding="utf-8")
    assert "_body_label.meta_clicked.connect(_on_body_meta_clicked)" in source
    assert "_body_label.meta_underlined = true" in source


def test_about_dialog_only_opens_http_and_https() -> None:
    source = ABOUT.read_text(encoding="utf-8")
    assert 'lower.begins_with("https://")' in source
    assert 'lower.begins_with("http://")' in source
    assert 'OS.shell_open(target)' in source
    assert 'mailto:' not in source
    assert 'file://' not in source
