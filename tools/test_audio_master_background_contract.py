#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Static contract for application audio, Library-backed background tracks and sliders."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file():
        raise AssertionError(f"missing file: {relative}")
    return path.read_text(encoding="utf-8")


def test_settings_schema_library_selection_and_interactive_debounce() -> None:
    settings = read("scripts/settings/app_settings_store.gd")
    for term in (
        "const SETTINGS_SCHEMA_VERSION: int = 18",
        "const DEFAULT_AUDIO_MASTER_VOLUME: float = 1.0",
        "const INTERACTIVE_BROADCAST_DEBOUNCE_SECONDS: float = 0.08",
        "var audio_master_enabled: bool = true",
        "var audio_master_volume: float = DEFAULT_AUDIO_MASTER_VOLUME",
        "var background_music_enabled: bool = false",
        "var background_music_volume: float = DEFAULT_BACKGROUND_MUSIC_VOLUME",
        'var background_music_track: String = ""',
        'var background_music_asset_id: String = ""',
        "if source_version < 17:",
        'if source_version < 18 and not migrated.has("background_music_asset_id"):',
        '"background_music_asset_id": background_music_asset_id',
        "func set_background_music_asset_id(value: String) -> void:",
        "func clear_background_music_selection() -> void:",
        "func _commit_change(interactive: bool = false) -> void:",
        "_interactive_broadcast_timer.start(INTERACTIVE_BROADCAST_DEBOUNCE_SECONDS)",
        "func _flush_pending_settings_broadcast() -> void:",
        'if not clean.begins_with(BACKGROUND_MUSIC_ROOT + "/"):',
    ):
        assert term in settings, f"settings contract missing: {term}"
    for setter_assignment in (
        "camera_sensitivity = normalized\n\t_commit_change(true)",
        "zoom_sensitivity = normalized\n\t_commit_change(true)",
        "camera_speed = normalized\n\t_commit_change(true)",
        "audio_master_volume = normalized\n\t_commit_change(true)",
        "background_music_volume = normalized\n\t_commit_change(true)",
    ):
        assert setter_assignment in settings, f"interactive setting is not debounced: {setter_assignment}"


def test_app_owned_audio_service_library_loading_and_ducking() -> None:
    service = read("scripts/media/app_audio_service.gd")
    for term in (
        "class_name AppAudioService",
        'const FOREGROUND_MEDIA_GROUP: StringName = &"notlight_foreground_media"',
        'const BACKGROUND_MUSIC_DIR: String = "res://assets/audio/background"',
        'const FEATURE_REFERENCE_OWNER: String = "app.background_music"',
        "signal library_tracks_changed(tracks: Array[Dictionary])",
        "func configure_library(library_service: AssetLibraryService, audio_service: AudioMediaService) -> void:",
        'library.list_assets("", AssetKinds.AUDIO)',
        "audio_media.load_stream(_active_asset_id)",
        "audio_media.playback_ready.connect(_on_audio_playback_ready)",
        "audio_media.playback_variant_changed.connect(_on_audio_playback_variant_changed)",
        "library.set_feature_asset_references(",
        "func _effective_library_asset_id() -> String:",
        "if not settings.background_music_enabled:",
        "asset_id != _effective_library_asset_id()",
        "ResourceLoader.list_directory(BACKGROUND_MUSIC_DIR)",
        'AudioServer.get_bus_index(&"Master")',
        "AudioServer.set_bus_mute",
        "AudioServer.set_bus_volume_db",
        "func apply_live_levels() -> void:",
        "func _has_audible_foreground_media() -> bool:",
        "audio_player.has_stream_playback() and not audio_player.stream_paused",
        "video_player.is_playing() and not video_player.paused",
        "var target_gain: float = 0.0 if _ducking else 1.0",
        "DUCK_ATTACK_PER_SECOND",
        "DUCK_RELEASE_PER_SECOND",
        "_background_player.volume_linear = music_volume * clampf(_duck_gain, 0.0, 1.0)",
        "func _on_background_finished() -> void:",
    ):
        assert term in service, f"audio service contract missing: {term}"
    assert service.count("func _clear_background_track(selection: Dictionary) -> void:") == 1
    assert 'FileAccess.open(' not in service, "background playback must not bypass managed Library resources"
    assert ":=" not in service


def test_feature_reference_index_protects_background_audio() -> None:
    refs = read("scripts/assets/asset_reference_index.gd")
    library = read("scripts/assets/asset_library_service.gd")
    card = read("scripts/ui/asset_library_card.gd")
    for term in (
        "func external_usage_count(asset_id: String) -> int:",
        "func external_labels_for(asset_id: String) -> PackedStringArray:",
        "func set_external_refs(owner_id: String, asset_ids: PackedStringArray, label: String = \"\") -> bool:",
        "return board_usage_count(asset_id) + note_embed_usage_count(asset_id) + external_usage_count(asset_id)",
    ):
        assert term in refs, f"feature reference contract missing: {term}"
    for term in (
        "func set_feature_asset_references(owner_id: String, asset_ids: PackedStringArray, label: String = \"\") -> void:",
        'enriched["feature_usage_count"] = references.external_usage_count(asset_id)',
        'record["used_by_features"] = references.external_labels_for(asset_id)',
        "if references.is_used(asset_id):",
    ):
        assert term in library, f"Library feature reference contract missing: {term}"
    assert 'record.get("feature_usage_count", 0)' in card
    assert 'NotLightL10n.bind_text(_usage_label, "library.usage.app_feature")' in card


def test_first_party_media_surfaces_participate_and_sliders_ignore_scroll() -> None:
    expected_media = (
        "scripts/ui/audio_board_player.gd",
        "scripts/ui/video_board_player.gd",
        "scripts/ui/video_player_overlay.gd",
        "scripts/ui/asset_preview_overlay.gd",
        "scripts/notes/note_resource_embed_block.gd",
    )
    for relative in expected_media:
        source = read(relative)
        assert "AppAudioService.FOREGROUND_MEDIA_GROUP" in source, f"foreground media group missing in {relative}"
    voice = read("scripts/media/voice_recording_service.gd")
    assert "AppAudioService.FOREGROUND_MEDIA_GROUP" not in voice, "muted microphone capture must not duck background music"

    slider_files = (
        "scripts/ui/settings_dialog.gd",
        "scripts/ui/formula_editor_panel.gd",
        "scripts/ui/video_board_player.gd",
        "scripts/ui/drawing_tool_palette.gd",
        "scripts/ui/audio_board_player.gd",
        "scripts/ui/stroke_context_toolbar.gd",
        "scripts/ui/asset_preview_overlay.gd",
        "scripts/notes/note_resource_embed_block.gd",
        "scripts/ui/video_player_overlay.gd",
    )
    for relative in slider_files:
        source = read(relative)
        created = source.count("HSlider.new()")
        disabled = source.count(".scrollable = false")
        assert created > 0, f"expected HSlider in {relative}"
        assert disabled >= created, f"scroll must be disabled for every HSlider in {relative}: {disabled}/{created}"


def test_settings_audio_page_and_app_wiring() -> None:
    dialog = read("scripts/ui/settings_dialog.gd")
    for term in (
        "const PAGE_AUDIO: int = 2",
        'NotLightL10n.text("settings.nav.audio")',
        "func _build_audio_page(parent: VBoxContainer) -> void:",
        "_audio_master_slider",
        "_background_music_option",
        "app_audio.library_tracks_changed.connect(_on_library_tracks_changed)",
        "app_audio.get_library_tracks()",
        'settings.set_background_music_asset_id(value)',
        "settings.clear_background_music_selection()",
        "app_audio.apply_live_levels()",
        "slider.scrollable = false",
    ):
        assert term in dialog, f"audio settings UI missing: {term}"
    app_root = read("scripts/app/app_root.gd")
    for term in (
        "var app_audio: AppAudioService",
        "app_audio = AppAudioService.new()",
        "app_audio.configure(settings)",
        "app_audio.configure_library(asset_library, audio_media)",
    ):
        assert term in app_root, f"AppRoot ownership missing: {term}"


def test_localization_and_author_drop_folder() -> None:
    keys = (
        "settings.nav.audio",
        "settings.audio.title",
        "settings.audio.master_enabled",
        "settings.audio.master_volume",
        "settings.audio.background_enabled",
        "settings.audio.background_volume",
        "settings.audio.background_track",
        "settings.audio.background_bundled_item",
        "settings.audio.background_library_item",
        "settings.audio.background_library_missing_item",
        "settings.audio.background_missing",
        "library.usage.app_feature",
        "library.usage.other_refs",
        "library.inspector.usage_features",
    )
    for locale in ("ru",):
        data = json.loads(read(f"localization/core/{locale}.json"))["strings"]
        for key in keys:
            assert key in data and str(data[key]).strip(), f"{locale} missing audio localization: {key}"
    guide = read("assets/audio/background/README_RU.txt")
    assert "res://assets/audio/background/" in guide
    assert ".ogg" in guide and ".mp3" in guide and ".wav" in guide


def test_audio_feature_files_keep_gplv3_or_later_headers() -> None:
    expected_headers = {
        "scripts/media/app_audio_service.gd": "# SPDX-License-Identifier: GPL-3.0-or-later",
        "tools/test_audio_master_background_contract.py": "# SPDX-License-Identifier: GPL-3.0-or-later",
        "docs/AUDIO_MASTER_AND_BACKGROUND_MUSIC.md": "<!-- SPDX-License-Identifier: GPL-3.0-or-later -->",
        "assets/audio/background/README_RU.txt": "SPDX-License-Identifier: GPL-3.0-or-later",
    }
    for relative, header in expected_headers.items():
        lines = read(relative).splitlines()[:3]
        assert header in lines, f"GPLv3+ SPDX header missing near top of {relative}"
