#!/usr/bin/env python3
"""Static guardrails for Notes rendering hardening and Module Library preview."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def require(text: str, needles: tuple[str, ...], label: str) -> None:
    missing = [needle for needle in needles if needle not in text]
    if missing:
        raise AssertionError(f"{label} missing: {', '.join(missing)}")


def main() -> int:
    embed = read("scripts/notes/note_resource_embed_block.gd")
    formula = read("scripts/notes/note_formula_block.gd")
    inline = read("scripts/notes/note_inline_markup.gd")
    inspector = read("scripts/ui/module_library_inspector.gd")
    library_view = read("scripts/ui/module_library_view.gd")
    preview_overlay = read("scripts/ui/module_preview_overlay.gd")
    hub_screen = read("scripts/ui/hub_screen.gd")
    ephemeral_host = read("scripts/modules/module_ephemeral_state_host.gd")
    preview_host = read("scripts/modules/module_preview_state_host.gd")
    module_embed = read("scripts/notes/note_module_embed.gd")
    module_embed_block = read("scripts/notes/note_module_embed_block.gd")
    preview_editor = read("scripts/notes/note_preview_editor.gd")
    board_preview_extractor = read("scripts/notes/note_board_preview_extractor.gd")
    formula_service = read("scripts/media/formula_render_service.gd")
    formula_worker = read("scripts/workers/formula_image_load_worker.gd")
    runtime_smoke = read("tools/stage11_9_runtime_smoke_test.gd")

    require(
        embed,
        (
            "AspectRatioContainer.new()",
            "AspectRatioContainer.STRETCH_FIT",
            "_update_video_aspect_from_texture",
            "get_video_texture()",
            "VIDEO_MAX_HEIGHT",
            '_audio_waveform.modulate = NotLightTheme.semantic_color("accent")',
        ),
        "aspect-preserving Notes video and accent waveform embed",
    )
    require(
        embed,
        (
            "ScrollContainer.new()",
            "PDF_ZOOM_MIN",
            "PDF_ZOOM_MAX",
            "PDF_MAX_REQUEST_EXTENT",
            "PDF_PAGE_MARGIN",
            "_update_pdf_geometry",
            "get_page_size(_asset_id)",
            "float(page_size.x) * _pdf_zoom",
            "maxf(viewport_width, scaled_width + PDF_PAGE_MARGIN * 2.0)",
            "floor((canvas_width - scaled_width) * 0.5)",
            "_on_pdf_zoom_in",
            "_on_pdf_zoom_out",
            "_on_pdf_zoom_reset",
        ),
        "centered natural-size in-embed PDF zoom",
    )
    require(
        formula_service,
        (
            'WRAPPER_VERSION: String = "notlight-formula-mitex-wrapper-v4-vector-guard-band"',
            '#set page(width: auto, height: auto, margin: 16pt, fill: none)',
            '#box(inset: 20pt)[#%s]',
        ),
        "pre-raster vector guard band for LaTeX glyph bounds",
    )
    require(
        formula_worker,
        (
            "ALPHA_TRIM_PADDING_MIN: int = 48",
            "ALPHA_TRIM_PADDING_RATIO: float = 0.08",
        ),
        "post-raster LaTeX alpha-trim safety padding",
    )

    require(
        formula,
        (
            "_layout_host = Control.new()",
            "_layout_host.clip_contents = false",
            "MAX_FORMULA_HEIGHT: float = 2200.0",
            "MAX_PRESENTATION_ROWS: int = 32",
            "PREFERRED_MULTI_LINE_WIDTH: float = 360.0",
            "PREVIEW_EXTENT_TALL: float = 2048.0",
            "_layout_host.resized.connect(_layout_texture)",
            "_layout_host.custom_minimum_size.y = reserved_height",
            "_texture.position = Vector2(",
            "_preview_extent_for_source",
        ),
        "explicit non-clipping multi-line Notes LaTeX layout",
    )

    wiki_start = inline.index('if text.substr(index, 2) == "[[":')
    wiki_end = inline.index('if text.substr(index, 3) == "***"', wiki_start)
    wiki_branch = inline[wiki_start:wiki_end]
    require(
        wiki_branch,
        (
            "[i]%s[/i]",
            "escape_bbcode(label)",
            "Wiki labels are a literal namespace",
        ),
        "literal italic wiki-link rendering",
    )
    if "to_bbcode(label" in wiki_branch:
        raise AssertionError("wiki-link labels still recurse into Markdown formatting")
    require(
        inline,
        (
            "_wiki_visible_source_range",
            "output += visible",
            "triple_close: int = position + 2",
            "_is_single_emphasis_opener",
            "_is_word_character(previous) and _is_word_character(following)",
        ),
        "nested/intraword Markdown hardening",
    )

    require(
        ephemeral_host,
        (
            "class_name ModuleEphemeralStateHost",
            "extends ModuleInstanceStateHost",
            "func configure_ephemeral(",
            "func detach() -> void:",
            "commit_normalized_state",
            "persist_normalized_state",
        ),
        "generic ephemeral module state host",
    )
    require(
        preview_host,
        (
            "class_name ModulePreviewStateHost",
            "extends ModuleEphemeralStateHost",
            "configure_ephemeral(",
            '"library-preview:%s"',
        ),
        "Module Library specialization of the generic ephemeral host",
    )
    for label, text in (("generic ephemeral host", ephemeral_host), ("preview host", preview_host)):
        if "BoardSession" in text or "UpdateModuleStateCommand" in text:
            raise AssertionError(f"{label} leaked board-specific persistence")
    require(
        inspector,
        (
            "signal preview_requested(module_id: String)",
            "func _request_preview() -> void:",
            "preview_requested.emit(module_id)",
            "modules.library.preview.start",
            'body_scroll.name = "ModuleInspectorBodyScroll"',
            "body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO",
            'NotLightL10n.bind_text(_embed_copy_button, "modules.library.embed.copy")',
            "NoteModuleEmbed.syntax_for_module(module_id)",
        ),
        "Module Library inspector metadata/preview/embed launcher",
    )
    if "ModuleSurfaceHost.new()" in inspector or "ModulePreviewStateHost.new()" in inspector:
        raise AssertionError("Module Library inspector still owns the live module simulation")
    require(
        preview_overlay,
        (
            "class_name ModulePreviewOverlay",
            "z_index = 1900",
            "ModuleSurfaceHost.new()",
            "ModulePreviewStateHost.new()",
            "func open_module(new_module_id: String) -> void:",
            "registry.default_state(module_id)",
            "_surface_host.materialize",
            "func close_preview() -> void:",
            "_state_host.detach()",
            "notlight_set_host_presentation",
            "push_host_locale()",
        ),
        "full-screen isolated Module Library preview overlay",
    )
    require(library_view, ("module_preview_requested", "_inspector.preview_requested.connect"), "Module Library preview request wiring")
    require(hub_screen, ("ModulePreviewOverlay.new()", "_module_view.module_preview_requested.connect(_open_module_preview)"), "Hub-level Module preview overlay wiring")
    require(
        module_embed,
        (
            "class_name NoteModuleEmbed",
            'const PREFIX: String = "![[module:"',
            "ModuleManifest.is_valid_module_id",
            "extract_module_ids",
            "MAX_EMBEDS_PER_NOTE: int = 256",
        ),
        "canonical Notes module embed syntax",
    )
    require(
        module_embed_block,
        (
            "class_name NoteModuleEmbedBlock",
            "ModuleEphemeralStateHost.new()",
            "STAGE_MIN_HEIGHT: float = 520.0",
            "_registry.default_state(_module_id)",
            "_surface_host.materialize",
            "live_activation_requested.emit(self)",
            "func deactivate_live() -> void:",
            "_state_host.detach()",
        ),
        "runtime-only Notes module embed surface",
    )
    if "BoardSession" in module_embed_block or "UpdateModuleStateCommand" in module_embed_block:
        raise AssertionError("Notes module embed leaked board-specific durable state")
    require(
        preview_editor,
        (
            "TYPE_MODULE_EMBED",
            "MAX_NOTE_MODULE_LIVE_SURFACES",
            "_module_live_budget",
            "_on_module_embed_live_activation_requested",
            'performance_budget.get("active_module_surfaces", 1)',
        ),
        "bounded Notes module embed lifecycle",
    )
    require(
        board_preview_extractor,
        (
            "NoteMarkdownBlocks.TYPE_MODULE_EMBED",
            "NoteModuleEmbed.parse_exact",
            '"module_id": module_id',
        ),
        "lightweight board preview representation for module embeds",
    )
    require(
        runtime_smoke,
        (
            "_test_note_inline_markup_runtime()",
            "_test_module_library_preview_runtime()",
            "_test_note_module_embed_runtime()",
            "Module Library overlay did not materialize an isolated live preview surface",
            "Notes module embed did not materialize an isolated live surface",
            "wiki-link title was not rendered as one literal italic label",
        ),
        "runtime regressions for Notes/Module preview",
    )

    changed_gd = (
        "scripts/notes/note_resource_embed_block.gd",
        "scripts/notes/note_formula_block.gd",
        "scripts/notes/note_inline_markup.gd",
        "scripts/notes/note_preview_editor.gd",
        "scripts/notes/note_module_embed.gd",
        "scripts/notes/note_module_embed_block.gd",
        "scripts/notes/note_board_preview_extractor.gd",
        "scripts/modules/module_ephemeral_state_host.gd",
        "scripts/modules/module_preview_state_host.gd",
        "scripts/ui/module_library_inspector.gd",
        "scripts/ui/module_library_view.gd",
        "scripts/ui/module_preview_overlay.gd",
        "scripts/ui/hub_screen.gd",
        "tools/stage11_9_runtime_smoke_test.gd",
    )
    for path in changed_gd:
        text = read(path)
        if ":=" in text:
            raise AssertionError(f"explicit typing policy violated by := in {path}")
        for line_number, line in enumerate(text.splitlines(), 1):
            if re.match(r"^\s*(?:var|const)\s+[A-Za-z_][A-Za-z0-9_]*\s*=", line):
                raise AssertionError(f"untyped variable/constant in {path}:{line_number}: {line.strip()}")

    print("Stage 11.9 Notes rendering + Module Library preview contract passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
