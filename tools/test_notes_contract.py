#!/usr/bin/env python3
"""Static regression checks for the Stage 11.5 Notes graph/Markdown/portability/storage hardening.

This intentionally complements validate_project.py. It checks the invariants that
matter most when Godot is not available in a source-handoff environment; the
runtime smoke script remains authoritative once Godot 4.4.1 is present.
"""
from __future__ import annotations

from pathlib import Path
import re
import sys

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


def check_no_implicit_typing() -> None:
    paths = [
        *sorted((ROOT / "scripts/notes").glob("*.gd")),
        *sorted((ROOT / "scripts/workers").glob("note_*.gd")),
        ROOT / "scripts/board/note_portal_batch_renderer.gd",
        ROOT / "scripts/core/note_portal_store.gd",
        ROOT / "scripts/notes/note_board_workspace_surface.gd",
        ROOT / "scripts/notes/note_board_surface_pool.gd",
        ROOT / "scripts/notes/notes_navigation_tree.gd",
        ROOT / "scripts/core/create_note_portal_command.gd",
        ROOT / "tools/notes_core_smoke_test.gd",
    ]
    for path in paths:
        text = path.read_text(encoding="utf-8")
        if ":=" in text:
            raise AssertionError(f"implicit := typing found in {path.relative_to(ROOT)}")
        # Catch a common merge/paste failure that is valid text but invalid GDScript.
        lines = text.splitlines()
        for index in range(1, len(lines)):
            if lines[index].strip() and lines[index] == lines[index - 1]:
                if lines[index].lstrip().startswith(("for ", "if ", "elif ", "while ", "func ")):
                    raise AssertionError(
                        f"duplicate control line at {path.relative_to(ROOT)}:{index + 1}"
                    )


def main() -> int:
    asset_kinds = read("scripts/assets/asset_kinds.gd")
    catalog = read("scripts/assets/asset_catalog.gd")
    library = read("scripts/assets/asset_library_service.gd")
    repo = read("scripts/notes/note_repository.gd")
    read_worker = read("scripts/workers/note_read_worker.gd")
    index_worker = read("scripts/workers/note_index_worker.gd")
    save_worker = read("scripts/workers/note_save_worker.gd")
    portal_store = read("scripts/core/note_portal_store.gd")
    schema = read("scripts/core/board_document_schema.gd")
    graph_model = read("scripts/notes/notes_graph_model.gd")
    graph_canvas = read("scripts/notes/notes_graph_canvas.gd")
    workspace = read("scripts/notes/note_workspace_overlay.gd")
    renderer = read("scripts/board/note_portal_batch_renderer.gd")
    board_view = read("scripts/board/native_board_view.gd")
    portable = read("scripts/portable/notlight_portable_package_service.gd")
    portable_format = read("scripts/portable/notlight_portable_package_format.gd")
    board_repository = read("scripts/data/board_repository.gd")
    module_registry = read("scripts/modules/module_registry.gd")
    module_packages = read("scripts/modules/module_package_service.gd")
    asset_card = read("scripts/ui/asset_library_card.gd")
    markdown_blocks = read("scripts/notes/note_markdown_blocks.gd")
    preview_editor = read("scripts/notes/note_preview_editor.gd")
    preview_extractor = read("scripts/notes/note_board_preview_extractor.gd")
    inline_markup = read("scripts/notes/note_inline_markup.gd")
    formula_block = read("scripts/notes/note_formula_block.gd")
    formula_store = read("scripts/core/formula_store.gd")
    link_parser = read("scripts/notes/note_link_parser.gd")
    navigation_tree = read("scripts/notes/notes_navigation_tree.gd")
    board_workspace = read("scripts/notes/note_board_workspace_surface.gd")
    surface_pool = read("scripts/notes/note_board_surface_pool.gd")
    board_screen = read("scripts/ui/board_screen.gd")
    asset_view = read("scripts/ui/asset_library_view.gd")
    smoke = read("tools/notes_core_smoke_test.gd")

    require(
        asset_kinds,
        (
            "const OTHER: int = 6",
            "const NOTE: int = 7",
            "static func is_board_insertable(kind: int) -> bool:",
            "kind == NOTE",
        ),
        "kind ABI / board insertion",
    )
    require(
        asset_card,
        (
            "AssetKinds.is_board_insertable(_kind)",
            "AssetKinds.is_previewable(_kind)",
        ),
        "Resource Library Note card UX",
    )
    require(
        catalog,
        (
            "current_kind != AssetKinds.NOTE",
            "allows_shared_hash: bool = int(asset.get(\"kind\", AssetKinds.OTHER)) == AssetKinds.NOTE",
            "int(asset.get(\"kind\", AssetKinds.OTHER)) != AssetKinds.NOTE",
        ),
        "logical-note identity",
    )
    cleanup = library[library.index("func cleanup_unused()"):]
    cleanup = cleanup[: cleanup.index("\nfunc ", 1)] if "\nfunc " in cleanup[1:] else cleanup
    require(cleanup, ("AssetKinds.NOTE", "continue"), "standalone-note cleanup protection")

    require(
        repo,
        (
            "CACHE_BYTE_BUDGET",
            "CACHE_ENTRY_BUDGET",
            "MAX_EXPLICIT_LINKS",
            "request_content_load",
            "request_save",
            "flush_pending_saves",
            "_dirty_content_by_id",
            "_index_waiting_head",
            "_index_waiting_count()",
            "_compact_index_waiting_queue()",
            "delete_blob_if_unreferenced_path",
            "local_relation_snapshot",
            "distance_by_id",
            "Build only the induced local subgraph",
            'return current_ids[0] if current_ids.size() == 1 else ""',
            'return alias_ids[0] if alias_ids.size() == 1 else ""',
            "NOTE_METADATA_SCHEMA_VERSION: int = 2",
            "link_aliases",
            "_alias_to_ids",
            "Current titles always outrank historical aliases",
            "original_metadata",
            'NotLightL10n.text("runtime.notes.rollback_failed")',
        ),
        "NoteRepository",
    )
    if '.push_front(' in repo:
        raise AssertionError("NoteRepository uses Array-only push_front() on a packed queue")
    if "_index_waiting_ids.remove_at(0)" in repo:
        raise AssertionError("NoteRepository index queue regressed to O(n) front removal")
    if r'\u0000' in repo:
        raise AssertionError("NoteRepository materializes a NUL Unicode literal in GDScript source")
    if r'\u0000' in formula_store:
        raise AssertionError("FormulaStore materializes a NUL Unicode literal in GDScript source")
    for worker_text, label in (
        (read_worker, "read worker"),
        (index_worker, "index worker"),
        (save_worker, "save worker"),
    ):
        require(worker_text, ("MAX_PENDING_JOBS", "Thread.new()", "Mutex.new()", "Semaphore.new()"), label)
    require(read_worker, ("expected_byte_size", "_sha256_hex(bytes)", "value == 0"), "read integrity")
    require(index_worker, ("expected_byte_size", "_sha256_hex(bytes)", "MAX_EXCERPT_CHARS"), "index integrity")

    require(portal_store, ('STORE_ID: StringName = &"note_portals"', '"asset_id": note_ids[index]'), "NotePortal store")
    require(schema, ("CURRENT_VERSION: int = 13", '"note_portals"', 'SINGLE_ASSET_REFERENCE_FIELDS'), "board schema")

    require(
        graph_model,
        (
            "MAX_NODES: int = 20000",
            "MAX_EDGES: int = 120000",
            "_spatial_cells",
            "_edge_indices_by_node",
            "query_edges_for_nodes",
            "build_reset_layout",
            "resolve_non_overlapping_position",
            "_fallback_non_overlapping_position",
            "LAYOUT_MIN_SPACING",
        ),
        "native graph model",
    )
    stock_graph_terms = ("Graph" + "Edit", "Graph" + "Node")
    if any(term in graph_canvas for term in stock_graph_terms):
        raise AssertionError("Notes graph gained a stock graph-control dependency")
    require(
        graph_canvas,
        (
            "event.shift_pressed",
            "relation_create_requested",
            "relation_remove_requested",
            "set_local_scope",
            "set_local_hops",
            "draw_circle",
            "draw_multiline",
            "MAX_VISIBLE_NODES",
            "MAX_VISIBLE_EDGES",
            "InputEventMagnifyGesture",
            "InputEventPanGesture",
            "app_settings.input_mode",
            "app_settings.camera_sensitivity",
            "app_settings.zoom_sensitivity",
            "app_settings.camera_speed",
            "NODE_DRAG_THRESHOLD_PIXELS",
            "reset_layout",
            "resolve_non_overlapping_position",
        ),
        "native scalable graph input/rendering",
    )
    graph_motion = graph_canvas[graph_canvas.index("func _handle_mouse_motion"): graph_canvas.index("func _handle_key")]
    require(
        graph_motion,
        (
            "NODE_DRAG_THRESHOLD_PIXELS",
            "model.set_position(_dragging_index",
            "CURSOR_MOVE",
        ),
        "graph node dragging",
    )
    if ".selection_changed.connect" in workspace or ".selection_changed.connect" in board_workspace:
        raise AssertionError("graph single-click selection is coupled to note opening/navigation")
    if "relation_snapshot()" in repo[repo.index("func local_relation_snapshot"): repo.index("func resolve_title")]:
        raise AssertionError("local graph regressed to scanning the full relation snapshot")

    require(
        markdown_blocks,
        (
            "TYPE_FRONTMATTER",
            "TYPE_MATH",
            "_frontmatter_end(lines)",
            "_is_list_line(text)",
            "_is_math_start(text)",
        ),
        "Markdown block/source-span parsing",
    )
    require(
        preview_editor,
        (
            r'var newline: String = "\r\n" if raw.contains("\r\n") else "\n"',
            'marker.trim_suffix(".").is_valid_int()',
            "NoteCodeEdit",
            "NoteRichText",
            "NoteCalloutPanel",
            "NoteFormulaBlock.new()",
            "DisplayServer.clipboard_set(editor.text)",
            "flush_pending_edits",
            'editor.focus_exited.connect(func() -> void: commit.call())',
            "content_replace_requested.emit",
            "source_edit_at_requested",
            "source_offset_for_visible_index",
            "get_line_range",
            'get_theme_font("normal_font")',
            "NoteScrollBar",
            "foldable",
            "_callout_fold_state",
        ),
        "editable preview / CRLF preservation",
    )
    require(
        link_parser,
        (
            "inline_ticks",
            "_fence_at(markdown, index)",
            "not _is_escaped(markdown, index)",
        ),
        "wiki-link extraction safety",
    )

    require(
        workspace,
        (
            "NotePreviewEditor.new()",
            "CodeEdit.new()",
            "NotesGraphCanvas.new()",
            "NotesNavigationTree.new()",
            "request_content_load(note_id)",
            "_graph.focus_note(note_id, false)",
            "_preview.flush_pending_edits()",
            "_begin_folder_rename",
            "_request_folder_delete",
            "_set_graph_local",
            "_set_graph_hops",
            "note_workspace_insert_requested",
        ),
        "Notes workspace",
    )
    require(
        navigation_tree,
        (
            "MAX_TREE_DEPTH",
            "_append_folder_branch",
            "_append_notes_to_parent",
            "_get_drag_data",
            "_can_drop_data",
            "_drop_data",
            "note_move_requested",
            "note_rename_requested",
            "folder_rename_requested",
            "edit_selected(true)",
            "scroll_to_item",
        ),
        "unified folder/note navigation tree",
    )
    require(
        renderer,
        (
            "candidate_ids: PackedInt64Array",
            "max_visible: int",
            "peek_board_preview",
            "_draw_markdown_preview",
            "_draw_code_run",
            "_draw_table_run",
            "_draw_math_run",
            "FormulaRenderService",
            "FULL_MAX_RENDER_RUNS",
            "FULL_MAX_FORMULA_REQUESTS_PER_DRAW",
            "full_render: bool",
        ),
        "retained Markdown NotePortal renderer",
    )
    require(board_view, ("RENDER_REFRESH_NOTE_PORTAL", "_perform_note_portal_refresh", "CreateNotePortalCommand.new(", "VIEW_WORKSPACE"), "board portal scheduler")
    require(
        portal_store,
        (
            "VIEW_WORKSPACE",
            "MAX_WORKSPACE_TABS",
            "workspace_tabs",
            "set_workspace_state",
            "get_workspace_tabs",
        ),
        "rich board Notes workspace state",
    )
    require(schema, ('"note_portals": ["workspace_tabs"]',), "workspace-tab portable dependency collection")
    require(
        board_workspace,
        (
            "NotesNavigationTree.new()",
            "NotePreviewEditor.new()",
            "NotesGraphCanvas.new()",
            "ScrollContainer.new()",
            "MAX_WORKSPACE_TABS",
            "_open_note(note_id, true)",
            "_build_graph_toolbar",
            "_create_note_from_sidebar",
            "_commit_folder_create",
        ),
        "rich board Notes workspace surface",
    )
    require(
        surface_pool,
        (
             "DEFAULT_MAX_ACTIVE_SURFACES: int = AppSettingsStore.DEFAULT_NOTE_WORKSPACE_SURFACES",
            "MAX_ACTIVE_SURFACES: int = AppSettingsStore.MAX_NOTE_WORKSPACE_SURFACES",
            "while _activation_order.size() >= max_active_surfaces",
            "close_surface(_activation_order[0])",
            "VIEW_WORKSPACE",
        ),
        "bounded board Notes surface pool",
    )
    require(
        asset_card,
        (
            "workspace_insert_requested",
            "notes.place_simple_on_board",
            "notes.place_workspace_on_board",
        ),
        "dual Resource Library note insertion",
    )
    require(asset_view, ("note_workspace_insert_requested",), "Library rich-note insertion signal")
    require(board_screen, ("_place_library_note_workspace", "VIEW_WORKSPACE", "_note_surface_pool.activate"), "board rich-note insertion/activation")
    require(preview_extractor, ("MAX_RUNS: int = 192", '"kind": "code"', '"kind": "math"', '"kind": "table"'), "bounded retained Markdown preview extraction")
    require(
        formula_block,
        (
            "FormulaRenderService",
            "FormulaStore.DISPLAY_BLOCK",
            "request_texture",
            "\\begin{aligned}",
            "_prepare_render_source",
            "StyleBoxEmpty.new()",
        ),
        "organic/sequential block LaTeX rendering",
    )
    if 'notes.math.ready' in formula_block:
        raise AssertionError("successful Formula blocks must not render a redundant ready badge")
    require(
        inline_markup,
        (
            "external://",
            "mailto:",
            "note://",
            'text.substr(index, 3) == "***"',
            "_find_strong_end",
            "_find_single_emphasis_end",
            "source_offset_for_visible_index",
            'text.substr(index - 1, 1) == "!"',
        ),
        "safe/nested Markdown inline rendering",
    )

    # Package imports must preserve logical Note identity rather than globally
    # de-duplicate Note records by SHA-256.
    require(
        portable,
        (
            "source_is_note",
            "same_id_record",
            "if int(asset.get(\"kind\", AssetKinds.OTHER)) != AssetKinds.NOTE:",
            "asset_id_map[source_id] = source_id",
        ),
        "portable Note identity",
    )

    require(
        portable,
        (
            '"include_notes": include_notes',
            '"omitted_note_ids"',
            "export_library_profile",
            "_board_omitted_note_ids",
            "BoardDocumentSchema.remap_asset_references(normalized_document, asset_id_map)",
            "verify_payload_hashes",
            '_staging_root = library_root.path_join("package_staging")',
        ),
        "portable Notes privacy/export policy",
    )
    require(
        portable_format,
        (
            "static func verify_payload_hashes",
            "input.seek(offset)",
            "input.get_position()",
            "HashingContext.HASH_SHA256",
            "_restore_export_backup_after_failure",
        ),
        "streamed portable post-commit verification",
    )
    require(
        library,
        (
            "prepare_external_library",
            "_validate_library_snapshot",
            "_validate_asset_snapshot_hashes",
            "_snapshot_blob_relpath_is_safe",
            "_file_size_absolute",
            "expected_size",
            "variant_size",
            "directory.is_link(entry)",
            "finalize_prepared_external_library",
            "mark_prepared_external_library_activated",
            "_prepared_external_catalog_sha256",
            '"NotLightLibrary"',
        ),
        "relocatable Resource Library",
    )
    require(
        module_registry,
        (
            "prepare_external_modules",
            "get_staging_directory",
            "directory.is_link(entry)",
            "finalize_prepared_external_modules",
            "mark_prepared_external_modules_activated",
            "_directory_tree_fingerprint",
            '"NotLightModules"',
        ),
        "relocatable Module Library",
    )
    require(module_packages, ("_staging_root", "registry.get_staging_directory()"), "module same-volume staging")
    require(
        board_repository,
        (
            "func duplicate_board",
            "import_board_snapshot",
            "duplicate(true)",
        ),
        "independent board duplication",
    )

    require(
        smoke,
        (
            "same-content notes collapsed their logical IDs",
            "ambiguous wiki title was guessed instead of rejected",
            "removing a portal deleted the canonical note",
            "native graph did not preserve textual+explicit edge provenance",
            "empty Markdown revision did not commit as zero bytes",
            "empty initial Markdown note creation failed",
            "local graph omitted the center note",
            "local graph exceeded the requested three-hop depth",
            "historical title alias did not preserve a wiki relation after rename",
            "graph reset layout allowed node circles to overlap",
        ),
        "runtime smoke coverage",
    )

    theme = read("scripts/ui/notlight_theme.gd")
    require(
        theme,
        (
            '&"NoteRichText"',
            '&"NoteNavigationTree"',
            '&"NoteBoardWorkspacePanel"',
            '&"NoteFormulaPanel"',
            'theme.set_color("default_color", "NoteRichText"',
            'theme.set_stylebox("panel", "NoteNavigationTree"',
            '&"NoteScrollBar"',
        ),
        "Notes native theme variations",
    )
    hub = read("scripts/ui/hub_screen.gd")
    about = read("scripts/ui/project_about_dialog.gd")
    require(hub, ("ProjectAboutDialog", '"about.title"', '"hub.about_tooltip"'), "About project Hub entry")
    require(about, ('"about.body"', '"about.footer"', "RichTextLabel.new()"), "About project dialog")

    settings_store = read("scripts/settings/app_settings_store.gd")
    settings_dialog = read("scripts/ui/settings_dialog.gd")
    video_pool = read("scripts/ui/video_player_pool.gd")
    board_screen = read("scripts/ui/board_screen.gd")
    asset_library_view = read("scripts/ui/asset_library_view.gd")
    hub_screen = read("scripts/ui/hub_screen.gd")
    board_screen = read("scripts/ui/board_screen.gd")
    app_root = read("scripts/app/app_root.gd")
    require(
        settings_store,
        (
            "custom_active_note_workspace_surfaces",
            '"active_note_workspace_surfaces"',
            "set_custom_active_note_workspace_surfaces",
            "prefer_maximum_fps",
            "var prefer_maximum_fps: bool = false",
            '"prefer_maximum_fps": prefer_maximum_fps',
            "MAX_VIDEO_PLAYERS: int = 64",
            "MAX_MODULE_SURFACES: int = 32",
            "MAX_NOTE_WORKSPACE_SURFACES: int = 32",
            "custom_full_note_card_render",
            '"full_note_card_render"',
            '"effective_full_note_card_render"',
        ),
        "Notes/performance settings contract",
    )
    require(
        settings_dialog,
        (
            "settings.performance.note_workspace_surfaces",
            "_on_note_workspace_budget_changed",
            "settings.performance.full_note_card_render",
            "_on_full_note_card_render_toggled",
            "settings.performance.prefer_maximum_fps",
        ),
        "Notes/performance settings UX",
    )
    require(
        board_screen,
        ("_active_note_workspace_budget", "set_active_surface_budget(_active_note_workspace_budget())"),
        "live Notes workspace budget handoff",
    )
    require(
        app_root,
        (
            "Engine.max_fps = 0",
            "DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)",
            "finalize_prepared_external_library",
            "finalize_prepared_external_modules",
            "settings.set_library_root(prepared_library_root)",
            "settings.set_module_root(prepared_module_root)",
            "mark_prepared_external_library_activated",
            "mark_prepared_external_modules_activated",
        ),
        "maximum FPS and clean-exit storage activation policy",
    )
    if "settings.set_library_root(new_root)" in settings_dialog or "settings.set_module_root(new_root)" in settings_dialog:
        raise AssertionError("Settings dialog must prepare external storage without activating a stale snapshot before clean exit")

    check_no_implicit_typing()

    for path in (ROOT / "scripts").rglob("*.gd"):
        lowered = path.read_text(encoding="utf-8").lower()
        if "ob" + "sidian" in lowered:
            raise AssertionError(f"foreign product name leaked into runtime code: {path.relative_to(ROOT)}")

    # Every new core runtime class must remain globally named so dependent typed
    # GDScript can resolve it without preload duplication.
    class_names: dict[str, Path] = {}
    for path in (ROOT / "scripts").rglob("*.gd"):
        match = re.search(r"^class_name\s+([A-Za-z_][A-Za-z0-9_]*)\s*$", path.read_text(encoding="utf-8"), re.MULTILINE)
        if match:
            name = match.group(1)
            if name in class_names:
                raise AssertionError(f"duplicate class_name {name}: {class_names[name]} / {path}")
            class_names[name] = path
    for required in (
        "NoteRepository",
        "NoteReadWorker",
        "NoteIndexWorker",
        "NoteSaveWorker",
        "NotePreviewEditor",
        "NoteWorkspaceOverlay",
        "NotesGraphModel",
        "NotesGraphCanvas",
        "NotePortalStore",
        "NotePortalBatchRenderer",
        "NotesNavigationTree",
        "NoteBoardWorkspaceSurface",
        "NoteBoardSurfacePool",
        "NoteFormulaBlock",
        "NoteBoardPreviewExtractor",
    ):
        if required not in class_names:
            raise AssertionError(f"missing global Notes class: {required}")

    print("Stage 11.5 Notes graph/Markdown/portability/storage static contract tests passed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"Stage 11.5 Notes static contract tests failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
