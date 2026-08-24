#!/usr/bin/env python3
"""Static contracts for Stage 11.9 Notes media embeds / Library UX hardening."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file():
        raise AssertionError(f"missing file: {relative}")
    return path.read_text(encoding="utf-8")


def require(text: str, terms: tuple[str, ...], label: str) -> None:
    missing = [term for term in terms if term not in text]
    if missing:
        raise AssertionError(f"{label} missing: {missing}")


def main() -> int:
    theme = read("scripts/ui/notlight_theme.gd")
    embed_block = read("scripts/notes/note_resource_embed_block.gd")
    preview = read("scripts/notes/note_preview_editor.gd")
    settings = read("scripts/settings/app_settings_store.gd")
    settings_ui = read("scripts/ui/settings_dialog.gd")
    references = read("scripts/assets/asset_reference_index.gd")
    library = read("scripts/assets/asset_library_service.gd")
    card = read("scripts/ui/asset_library_card.gd")
    inspector = read("scripts/ui/asset_inspector_panel.gd")
    library_view = read("scripts/ui/asset_library_view.gd")
    formula_block = read("scripts/notes/note_formula_block.gd")
    formula_worker = read("scripts/workers/formula_image_load_worker.gd")
    portable = read("scripts/portable/notlight_portable_package_service.gd")

    # Bold/italic must use real system style selection, not synthetic emboldening
    # that produced visible glyph artifacts on Cyrillic/Latin text.
    require(
        theme,
        (
            "var note_base_font: SystemFont = SystemFont.new()",
            "note_bold_font.font_weight = 700",
            "note_italic_font.font_italic = true",
            "note_bold_italic_font.font_weight = 700",
            "note_bold_italic_font.font_italic = true",
            'theme.set_font("bold_font", "NoteRichText", note_bold_font)',
            '&"NoteEmbeddedMediaFrame"',
            '&"AssetFolderTree"',
        ),
        "real NoteRichText fonts and native embed/tree styles",
    )
    note_theme_region = theme[theme.find('&"NoteRichText"') : theme.find('&"NoteScrollBar"') if '&"NoteScrollBar"' in theme else len(theme)]
    if "variation_embolden" in note_theme_region:
        raise AssertionError("NoteRichText returned to synthetic FontVariation emboldening")

    require(
        embed_block,
        (
            "var _video_player: VideoStreamPlayer",
            "var _audio_player: AudioStreamPlayer",
            "var _pdf_view: TextureRect",
            "ClassDB.class_exists(\"FFmpegVideoStream\")",
            "_video_player.stream_position = _saved_position",
            "_audio_player.play(_saved_position)",
            "_audio_player.seek(_saved_position)",
            "_pdf_media.request_page",
            "_image_cache.request_texture",
            "live_activation_requested.emit(self)",
            "PROCESS_INTERVAL_SECONDS: float = 0.12",
            "Metadata-only Library changes must not tear down an active decoder/player",
        ),
        "bounded rich media embeds",
    )
    # Video thumbnails must not synchronously invoke FFmpeg merely because a Note rebuilt.
    if "get_thumbnail(_asset_id)" in embed_block and "thumbnail_path(_asset_id)" not in embed_block:
        raise AssertionError("Notes video embed can request an unbounded synchronous thumbnail without cache guard")

    require(
        preview,
        (
            "var _embed_live_budget: int",
            "var _embed_rich_preview: bool",
            "while _embed_live_order.size() >= _embed_live_budget",
            "oldest.deactivate_live()",
            'snapshot.get("effective_note_embed_live_media"',
            'snapshot.get("effective_note_embed_rich_preview"',
        ),
        "Notes media LRU/budget policy",
    )
    require(
        settings,
        (
            "const SETTINGS_SCHEMA_VERSION: int = 20",
            "const MAX_NOTE_EMBED_LIVE_MEDIA: int = 64",
            "var custom_note_embed_live_media: int",
            "var custom_note_embed_rich_preview: bool",
            '"note_embed_live_media"',
            '"note_embed_rich_preview"',
        ),
        "scalable Notes media performance settings",
    )
    require(
        settings_ui,
        (
            "_note_embed_live_budget_spin",
            "_note_embed_rich_preview_check",
            "set_custom_note_embed_live_media",
            "set_custom_note_embed_rich_preview",
        ),
        "performance settings UI",
    )

    require(
        references,
        (
            "func board_usage_count(asset_id: String) -> int:",
            "func note_embed_usage_count(asset_id: String) -> int:",
            "return board_usage_count(asset_id) + note_embed_usage_count(asset_id)",
            "func note_ids_for(asset_id: String) -> PackedStringArray:",
            "func board_entries_for(asset_id: String) -> Array[Dictionary]:",
        ),
        "board/note usage provenance",
    )
    require(
        library,
        (
            'record["board_usage_count"]',
            'record["note_embed_usage_count"]',
            'record["used_on_boards"]',
            'record["used_on_board_entries"]',
            'record["embedded_in_notes"]',
            'record["embedded_in_note_entries"]',
            "func _note_embed_names_for(asset_id: String) -> PackedStringArray:",
            "func _note_embed_entries_for(asset_id: String) -> Array[Dictionary]:",
        ),
        "Library usage enrichment",
    )
    require(
        card,
        (
            '"library.usage.boards_and_notes"',
            '"library.usage.boards"',
            '"library.usage.notes"',
        ),
        "resource card usage breakdown",
    )
    require(
        inspector,
        (
            '"library.inspector.usage_boards"',
            '"library.inspector.usage_notes"',
            '"used_on_boards"',
            '"used_on_board_entries"',
            '"embedded_in_notes"',
            '"embedded_in_note_entries"',
            '"board_usage_count"',
            '"note_embed_usage_count"',
            "entry_id.right(8)",
        ),
        "inspector usage breakdown",
    )

    require(
        library_view,
        (
            "var _folder_tree: Tree",
            "var _collapsed_folder_ids: Dictionary = {}",
            'theme_type_variation = "AssetFolderTree"',
            "set_column_clip_content(0, true)",
            "scroll_horizontal_enabled = false",
            "item.set_tooltip_text(0, library.folder_path(folder_id))",
            "item.collapsed = _collapsed_folder_ids.has(folder_id)",
            "item_collapsed.connect(_on_folder_tree_item_collapsed)",
        ),
        "bounded hierarchical Library folder tree",
    )

    require(
        formula_worker,
        (
            "ALPHA_TRIM_PADDING_MIN: int = 48",
            "ALPHA_TRIM_PADDING_MAX: int = 128",
            "ALPHA_TRIM_PADDING_RATIO: float = 0.08",
            "image.get_used_rect()",
            "image.get_region(region)",
        ),
        "formula alpha trim safety",
    )
    require(
        formula_block,
        (
            "MAX_FORMULA_HEIGHT: float = 2200.0",
            "MAX_PRESENTATION_ROWS: int = 32",
            "PREFERRED_MULTI_LINE_WIDTH: float = 360.0",
            "PREVIEW_EXTENT_TALL: float = 2048.0",
            "_layout_host.custom_minimum_size.y = reserved_height",
            "_presentation_row_count()",
            "_layout_texture()",
            "TextureRect.STRETCH_KEEP_ASPECT_CENTERED",
        ),
        "multi-row formula presentation sizing",
    )

    require(
        portable,
        (
            "Canonical blob Notes embed не прошёл SHA-256 проверку перед экспортом.",
            "func _validate_materialized_note_embed_closure(",
            "func _read_import_note_content(",
            "dependency_hashes",
            "referenced_hashes",
            'var record_value: Variant = asset.get("record", {})',
            "Notes embed dependency без корректного SHA-256",
        ),
        "portable embed dependency verification",
    )

    ru = json.loads(read("localization/core/ru.json"))["strings"]
    for key in (
        "settings.performance.note_embed_live_media",
        "settings.performance.note_embed_rich_preview",
        "library.usage.boards_and_notes",
        "library.inspector.usage_boards",
        "library.inspector.usage_notes",
        "notes.embed.show_inline",
        "notes.embed.page",
    ):
        if key not in ru or not str(ru[key]).strip():
            raise AssertionError(f"missing canonical RU localization key: {key}")

    changed_files = (
        "scripts/ui/notlight_theme.gd",
        "scripts/notes/note_resource_embed_block.gd",
        "scripts/notes/note_preview_editor.gd",
        "scripts/settings/app_settings_store.gd",
        "scripts/ui/settings_dialog.gd",
        "scripts/assets/asset_reference_index.gd",
        "scripts/assets/asset_library_service.gd",
        "scripts/ui/asset_library_card.gd",
        "scripts/ui/asset_inspector_panel.gd",
        "scripts/ui/asset_library_view.gd",
        "scripts/notes/note_formula_block.gd",
        "scripts/workers/formula_image_load_worker.gd",
        "scripts/portable/notlight_portable_package_service.gd",
    )
    for relative in changed_files:
        text = read(relative)
        if ":=" in text:
            raise AssertionError(f"implicit := typing found in {relative}")
        if "\x00" in text:
            raise AssertionError(f"NUL byte found in {relative}")
        if re.search(r"Transform2D\([^\n)]*,[^\n)]*,[^\n)]*,[^\n)]*,[^\n)]*,[^\n)]*\)", text):
            raise AssertionError(f"unsupported six-scalar Transform2D constructor found in {relative}")

    print("Stage 11.9 Notes media embeds / Library UX / portability contracts passed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"Stage 11.9 contract tests failed: {exc}")
        raise SystemExit(1)
