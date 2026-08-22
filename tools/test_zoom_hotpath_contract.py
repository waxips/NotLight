#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def require(text: str, terms: tuple[str, ...], label: str) -> None:
    for term in terms:
        if term not in text:
            raise AssertionError(f"{label} is missing: {term}")


def main() -> int:
    projection = read("scripts/ui/board_live_surface_projection.gd")
    note_pool = read("scripts/notes/note_board_surface_pool.gd")
    module_pool = read("scripts/modules/module_surface_pool.gd")
    video_pool = read("scripts/ui/video_player_pool.gd")
    audio_pool = read("scripts/ui/audio_player_pool.gd")
    video_player = read("scripts/ui/video_board_player.gd")
    audio_player = read("scripts/ui/audio_board_player.gd")
    module_library = read("scripts/ui/module_library_view.gd")
    board_screen = read("scripts/ui/board_screen.gd")

    require(
        projection,
        (
            "class_name BoardLiveSurfaceProjection",
            "LAYOUT_ZOOM_BASE: float = 1.32",
            "MIN_LAYOUT_ZOOM: float = 0.50",
            "MAX_LAYOUT_ZOOM: float = 2.00",
            "layout_zoom_for",
            "transform_scale_for",
        ),
        "quantized live-surface projection",
    )

    for label, text in (
        ("Notes surface pool", note_pool),
        ("Module surface pool", module_pool),
        ("Video player pool", video_pool),
        ("Audio player pool", audio_pool),
    ):
        if "func _process(_delta: float)" in text:
            raise AssertionError(f"{label} must not poll/reproject every frame")
        require(
            text,
            (
                "BoardLiveSurfaceProjection.layout_zoom_for(view_zoom)",
                "BoardLiveSurfaceProjection.transform_scale_for(view_zoom, layout_zoom)",
                "view_transform_changed.connect",
                "runtime_changed.connect",
            ),
            label,
        )

    require(
        note_pool,
        (
            "host.scale = Vector2.ONE * transform_scale",
            '"note_surface_layout_reflows"',
        ),
        "Notes zoom hot path",
    )
    require(
        module_pool,
        (
            "host.scale = Vector2.ONE * transform_scale",
            '"module_surface_layout_reflows"',
        ),
        "Module zoom hot path",
    )
    require(
        video_pool,
        (
            "player.scale = Vector2.ONE * transform_scale",
            '"video_surface_layout_reflows"',
        ),
        "Video zoom hot path",
    )
    require(
        audio_pool,
        (
            "player.scale = Vector2.ONE * transform_scale",
            '"audio_surface_layout_reflows"',
        ),
        "Audio zoom hot path",
    )

    require(
        video_player,
        (
            "_inline_layout_signature",
            "_responsive_layout_signature",
            "if next_signature == _inline_layout_signature:",
        ),
        "video responsive-layout debounce",
    )
    require(
        audio_player,
        (
            "_layout_signature",
            "_responsive_layout_signature",
            "if next_signature == _layout_signature:",
        ),
        "audio responsive-layout debounce",
    )

    for path in (ROOT / "scripts").rglob("*.gd"):
        text = path.read_text(encoding="utf-8")
        if "draw_colored_polygon(" in text:
            raise AssertionError(
                f"triangle-style CanvasItem rendering must use the fixed-size primitive path: {path.relative_to(ROOT)}"
            )

    if "_grid.size =" in module_library:
        raise AssertionError("Module Library must not assign size to a TOP_WIDE anchored GridContainer")
    require(
        module_library,
        ("_grid.offset_bottom = minimum_height",),
        "Godot 4.4.1 Module Library layout warning fix",
    )

    for key in (
        "_note_surface_pool.get_developer_diagnostics_snapshot()",
        "_module_surface_pool.get_developer_diagnostics_snapshot()",
        "_video_player_pool.get_developer_diagnostics_snapshot()",
        "_audio_player_pool.get_developer_diagnostics_snapshot()",
    ):
        if key not in board_screen:
            raise AssertionError(f"developer diagnostics is missing hot-path counters: {key}")

    print("Stage 11.6 zoom/live-surface hot-path contract tests passed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"Stage 11.6 hot-path contract tests failed: {exc}")
        raise SystemExit(1)
