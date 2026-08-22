#!/usr/bin/env python3
"""Static contracts for Stage 11.7 editor/Markdown/formula UX hardening."""

from __future__ import annotations

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
    library_service = read("scripts/assets/asset_library_service.gd")
    library_view = read("scripts/ui/asset_library_view.gd")
    inspector = read("scripts/ui/asset_inspector_panel.gd")
    workspace = read("scripts/notes/note_workspace_overlay.gd")
    theme = read("scripts/ui/notlight_theme.gd")
    inline = read("scripts/notes/note_inline_markup.gd")
    formula_block = read("scripts/notes/note_formula_block.gd")
    formula_worker = read("scripts/workers/formula_image_load_worker.gd")

    require(
        library_service,
        (
            "signal asset_metadata_changed(asset_id: String)",
            "asset_metadata_changed.emit(asset_id)",
        ),
        "narrow Resource Library metadata invalidation",
    )
    update_start = library_service.find("func update_asset_details")
    update_end = library_service.find("\n\nfunc ", update_start + 1)
    update_slice = library_service[update_start:update_end if update_end >= 0 else len(library_service)]
    if "library_changed.emit()" in update_slice:
        raise AssertionError("description/tag autosave must not fan out through coarse library_changed")
    require(
        library_view,
        (
            "library.asset_metadata_changed.connect(_on_asset_metadata_changed)",
            "func _on_asset_metadata_changed(_asset_id: String) -> void:",
        ),
        "Resource Library metadata-only refresh",
    )

    require(
        inspector,
        (
            "DESCRIPTION_SAVE_DELAY: float = 1.10",
            "_description_edit.focus_exited.connect(_flush_description)",
            "_self_library_update_depth",
            "_update_asset_details_without_self_refresh",
            "_refresh_record(true)",
            "_description_edit.get_caret_line()",
            "_description_edit.get_caret_column()",
            "_description_edit.scroll_vertical",
            "_description_edit.scroll_horizontal",
            "if _description_edit.text != next_description:",
        ),
        "Resource Library description autosave UX",
    )
    if "_dirty_description = false\n\tif library.update_asset_details" in inspector:
        raise AssertionError("description autosave must not clear dirty state before its own synchronous Library signal")

    require(
        workspace,
        (
            "if not _title_edit.has_focus():",
            "if _title_edit.text != next_title:",
        ),
        "Notes title self-refresh UX",
    )

    require(
        inline,
        (
            '"[b][i]%s[/i][/b]"',
            '"[b]%s[/b]"',
            '"[i]%s[/i]"',
        ),
        "Markdown emphasis parser",
    )
    require(
        theme,
        (
            'theme.set_font("normal_font", "NoteRichText", note_base_font)',
            'theme.set_font("bold_font", "NoteRichText", note_bold_font)',
            'theme.set_font("italics_font", "NoteRichText", note_italic_font)',
            'theme.set_font("bold_italics_font", "NoteRichText", note_bold_italic_font)',
            "note_bold_font.font_weight = 700",
            "note_italic_font.font_italic = true",
            "note_bold_italic_font.font_weight = 700",
            "note_bold_italic_font.font_italic = true",
        ),
        "Godot 4.4.1 RichTextLabel emphasis fonts",
    )

    require(
        formula_worker,
        (
            "image.get_used_rect()",
            "image.get_region(region)",
            "ALPHA_TRIM_PADDING_MIN",
            "ALPHA_TRIM_PADDING_MAX",
        ),
        "formula alpha-bound raster trim",
    )
    if "used.end." in formula_worker:
        raise AssertionError("formula crop should use position+size rather than depend on Rect2i.end")

    require(
        formula_block,
        (
            "SINGLE_LINE_DISPLAY_HEIGHT",
            "EXTRA_ROW_DISPLAY_HEIGHT",
            "_presentation_row_count()",
            "_prepare_aligned_line",
            'return "\\\\begin{aligned}%s\\\\end{aligned}"',
            "TextureRect.STRETCH_KEEP_ASPECT_CENTERED",
        ),
        "Notes formula presentation sizing/alignment",
    )
    if "custom_minimum_size = source_size" in formula_block:
        raise AssertionError("formula raster pixel resolution must not be reused as logical Notes UI size")

    for relative in (
        "scripts/ui/asset_inspector_panel.gd",
        "scripts/ui/notlight_theme.gd",
        "scripts/notes/note_formula_block.gd",
        "scripts/workers/formula_image_load_worker.gd",
        "scripts/notes/note_workspace_overlay.gd",
    ):
        text = read(relative)
        if ":=" in text:
            raise AssertionError(f"implicit := typing found in {relative}")
        if "\x00" in text:
            raise AssertionError(f"NUL byte found in {relative}")

    print("Stage 11.7 editor/Markdown/formula UX contract tests passed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"Stage 11.7 UX contract tests failed: {exc}")
        raise SystemExit(1)
