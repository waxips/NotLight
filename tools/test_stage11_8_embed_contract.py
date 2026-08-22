#!/usr/bin/env python3
"""Static contracts for Stage 11.8 Godot 4.4.1 fix + Notes Library embeds."""

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
    embed = read("scripts/notes/note_resource_embed.gd")
    embed_block = read("scripts/notes/note_resource_embed_block.gd")
    markdown_blocks = read("scripts/notes/note_markdown_blocks.gd")
    inline = read("scripts/notes/note_inline_markup.gd")
    links = read("scripts/notes/note_link_parser.gd")
    repository = read("scripts/notes/note_repository.gd")
    library = read("scripts/assets/asset_library_service.gd")
    references = read("scripts/assets/asset_reference_index.gd")
    portable = read("scripts/portable/notlight_portable_package_service.gd")
    export_dialog = read("scripts/ui/board_export_options_dialog.gd")
    card = read("scripts/ui/asset_library_card.gd")
    preview_extractor = read("scripts/notes/note_board_preview_extractor.gd")
    portal_renderer = read("scripts/board/note_portal_batch_renderer.gd")

    # The runtime error reported by Godot 4.4.1 is caused by the unsupported
    # six-scalar GDScript Transform2D constructor. Keep the documented three-
    # Vector2 constructor instead and ensure the bad spelling cannot return.
    if re.search(r"Transform2D\([^\n)]*,[^\n)]*,[^\n)]*,[^\n)]*,[^\n)]*,[^\n)]*\)", theme):
        raise AssertionError("six-scalar Transform2D constructor returned to notlight_theme.gd")
    require(
        theme,
        (
            "note_bold_font.font_weight = 700",
            "note_italic_font.font_italic = true",
            'theme.set_font("bold_font", "NoteRichText", note_bold_font)',
            'theme.set_font("italics_font", "NoteRichText", note_italic_font)',
            'theme.set_font("bold_italics_font", "NoteRichText", note_bold_italic_font)',
            '&"NoteResourceEmbedPanel"',
        ),
        "Godot 4.4.1 typography/embed theme",
    )

    require(
        embed,
        (
            'const PREFIX: String = "![[resource-sha256:"',
            "const MAX_EMBEDS_PER_NOTE: int = 512",
            "AssetKinds.IMAGE",
            "AssetKinds.VIDEO",
            "AssetKinds.AUDIO",
            "AssetKinds.PDF",
            "static func extract_hashes(markdown: String) -> PackedStringArray:",
            "inline_ticks",
            "in_fence",
        ),
        "canonical SHA-256 embed syntax/parser",
    )
    if '.replace("[", "(").replace("]", ")")' not in embed:
        raise AssertionError("generated embed captions must not be able to terminate canonical embed syntax")

    require(
        markdown_blocks,
        ("const TYPE_EMBED", "NoteResourceEmbed.parse_exact(text)"),
        "Markdown block embed recognition",
    )
    require(
        inline,
        (
            "NoteResourceEmbed.PREFIX",
            '"[b]%s[/b]"',
            '"[i]%s[/i]"',
            '"[b][i]%s[/i][/b]"',
        ),
        "inline Markdown/Cyrillic-neutral formatting",
    )
    # Emphasis parsing must not be restricted to Latin word classes.
    for forbidden in ("[A-Za-z]", "[a-zA-Z]", "\\w+"):
        if forbidden in inline:
            raise AssertionError(f"inline emphasis unexpectedly depends on Latin/ASCII class: {forbidden}")

    require(
        links,
        ('not (index > 0 and markdown.substr(index - 1, 1) == "!")',),
        "resource embeds excluded from note graph wiki-links",
    )
    require(
        embed_block,
        (
            "library.find_asset_by_hash(_hash_sha256)",
            "_image_cache.request_texture",
            "preview_requested.emit(_asset_id)",
        ),
        "runtime embed resolution/presentation",
    )
    require(
        preview_extractor,
        ("NoteMarkdownBlocks.TYPE_EMBED", '"kind": "embed"'),
        "lightweight board embed preview",
    )
    require(portal_renderer, ('elif kind == "embed":', "func _draw_embed_run"), "retained embed drawing")

    require(
        repository,
        (
            "func _refresh_resource_embeds(note_id: String, content: String) -> void:",
            "library.set_note_embed_hash_references",
        ),
        "NoteRepository embed reference indexing",
    )
    require(
        references,
        (
            "var _notes_by_asset: Dictionary = {}",
            "func set_note_embed_refs",
            "func note_ids_for",
            "return board_usage_count(asset_id) + note_embed_usage_count(asset_id)",
        ),
        "Library usage protection for note embeds",
    )
    require(
        library,
        (
            "func find_asset_by_hash",
            "func set_note_embed_hash_references",
            "_synchronize_note_embed_references_for_cleanup()",
            "references.note_ids_for(asset_id).size() > 0",
            "canonical blob: его SHA-256 закреплён embed-ссылкой",
        ),
        "pinned SHA lifecycle protection",
    )

    require(
        portable,
        (
            '"include_note_embeds": true',
            "_collect_note_embed_dependencies(note_ids)",
            '"note_embed_asset_ids"',
            "library.find_asset_by_hash(hash_sha256)",
            "if include_note_embeds:",
            "embedded_set[dependency_id] = true",
            '"note_embed_dependency_ids"',
            'library_manifest.get("note_embed_dependency_ids", [])',
            'assets_by_id.has(dependency_id)',
        ),
        "portable embed dependency closure",
    )
    if portable.count("var export_seen: Dictionary = _string_set(export_asset_ids)") != 1:
        raise AssertionError("export_board_profile must declare export_seen exactly once")
    require(
        export_dialog,
        (
            "var _include_note_embeds: CheckBox",
            '"exchange.board.include_note_embeds"',
            '"include_note_embeds"',
        ),
        "board export embed privacy option",
    )
    require(
        card,
        (
            "MENU_COPY_NOTE_EMBED",
            "NoteResourceEmbed.syntax_for_hash",
            "DisplayServer.clipboard_set(embed_syntax)",
        ),
        "Library copy-embed affordance",
    )

    fixture = read("test_notes/NOTLIGHT_MARKDOWN_FEATURE_TEST_STAGE11_8.md")
    require(
        fixture,
        (
            "**Жирный кириллический текст**",
            "*Курсивный кириллический текст*",
            "***Жирный курсив кириллицей***",
            "![[resource-sha256:",
        ),
        "Cyrillic Markdown/embed fixture",
    )

    ru = json.loads(read("localization/core/ru.json"))["strings"]
    for key in (
        "notes.embed.copy_action",
        "notes.embed.missing_hash",
        "exchange.board.include_note_embeds",
        "exchange.board.note_embed_dependency_help",
    ):
        if key not in ru or not str(ru[key]).strip():
            raise AssertionError(f"missing canonical RU localization key: {key}")

    changed_files = (
        "scripts/ui/notlight_theme.gd",
        "scripts/notes/note_resource_embed.gd",
        "scripts/notes/note_resource_embed_block.gd",
        "scripts/notes/note_markdown_blocks.gd",
        "scripts/notes/note_inline_markup.gd",
        "scripts/notes/note_link_parser.gd",
        "scripts/notes/note_repository.gd",
        "scripts/assets/asset_library_service.gd",
        "scripts/assets/asset_reference_index.gd",
        "scripts/portable/notlight_portable_package_service.gd",
        "scripts/ui/board_export_options_dialog.gd",
    )
    for relative in changed_files:
        text = read(relative)
        if ":=" in text:
            raise AssertionError(f"implicit := typing found in {relative}")
        if "\x00" in text:
            raise AssertionError(f"NUL byte found in {relative}")

    print("Stage 11.8 Godot 4.4.1 fix / Notes SHA-256 embed contracts passed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"Stage 11.8 embed contract tests failed: {exc}")
        raise SystemExit(1)
