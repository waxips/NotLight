#!/usr/bin/env python3
"""Stage 11.9 architecture/runtime-hardening source contract.

This is deliberately complementary to the real Godot runtime smoke. It prevents
future refactors from silently restoring the exact ownership/reentrancy patterns
that caused the Stage 11.9 regressions.
"""
from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def function_body(source: str, name: str) -> str:
    match = re.search(rf"^func {re.escape(name)}\([^\n]*\).*?:\n", source, re.MULTILINE)
    if match is None:
        raise AssertionError(f"missing function {name}")
    start = match.end()
    next_func = re.search(r"^func ", source[start:], re.MULTILINE)
    end = start + next_func.start() if next_func is not None else len(source)
    return source[start:end]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def test_tree_reentrancy_boundary() -> None:
    source = read("scripts/ui/asset_library_view.gd")
    select_body = function_body(source, "_select_folder")
    refresh_body = function_body(source, "_refresh_folders")
    require("_refresh_folders()" not in select_body, "folder selection must not structurally rebuild its own Tree")
    require("_refresh()" in select_body, "folder selection must still refresh filtered assets")
    require("_request_folder_tree_rebuild()" in refresh_body, "folder structural refresh must cross the deferred rebuild boundary")
    require("call_deferred(\"_run_deferred_folder_tree_rebuild\")" in source, "folder Tree rebuild is no longer deferred/coalesced")
    require("if root_item == null:" in source and "if item == null:" in source, "TreeItem allocation lost its null guards")
    runtime = read("tools/stage11_9_runtime_smoke_test.gd")
    require("folder selection synchronously rebuilt its own Tree" in runtime, "real runtime Tree regression assertion is missing")
    require("TreeItem.select() drives the real Tree item_selected signal path" in runtime, "runtime smoke no longer exercises real Tree selection")


def test_schema_aware_asset_remap() -> None:
    schema = read("scripts/core/board_document_schema.gd")
    portable = read("scripts/portable/notlight_portable_package_service.gd")
    require("SINGLE_ASSET_REFERENCE_FIELDS" in schema and "MULTI_ASSET_REFERENCE_FIELDS" in schema, "board asset references are no longer schema-declared")
    require("ModuleObject.instance_state is intentionally opaque" in schema, "opaque module-state portability invariant is undocumented")
    require("_collect_asset_ids_from_variant" not in schema, "generic magic-key asset collector returned")
    require("static func remap_asset_references" in schema, "schema-owned asset remapper is missing")
    require("BoardDocumentSchema.remap_asset_references(normalized_document, asset_id_map)" in portable, "portable import bypasses schema-owned remapping")
    require("func _remap_asset_ids(" not in portable, "portable service recursively rewrites arbitrary dictionaries again")
    runtime = read("tools/stage11_9_runtime_smoke_test.gd")
    require("portable import rewrote opaque module.instance_state" in runtime, "end-to-end opaque module state remap regression is missing")


def test_board_independent_module_host() -> None:
    context = read("scripts/modules/module_instance_context.gd")
    surface_host = read("scripts/modules/module_surface_host.gd")
    board_host = read("scripts/modules/board_module_instance_state_host.gd")
    pool = read("scripts/modules/module_surface_pool.gd")
    require("ModuleInstanceStateHost" in context, "ModuleInstanceContext does not delegate state ownership")
    require("BoardSession" not in context, "ModuleInstanceContext is board-coupled again")
    require("UpdateModuleStateCommand" not in context, "SDK context owns board undo semantics again")
    require("func materialize(" in surface_host and "parent: Control" in surface_host, "shared module surface materializer is missing")
    require("extends ModuleInstanceStateHost" in board_host, "board state host does not implement the shared state-host boundary")
    require("UpdateModuleStateCommand" in board_host, "board undo semantics did not stay in the board-specific state host")
    require("ModuleSurfaceHost.new()" in pool and "BoardModuleInstanceStateHost.new()" in pool, "board surface pool bypasses the shared module host boundary")
    runtime = read("tools/stage11_9_runtime_smoke_test.gd")
    require("_test_board_independent_module_surface_host" in runtime, "board-independent module materialization lacks a Godot runtime smoke")


def test_graph_provenance_stats() -> None:
    model = read("scripts/notes/notes_graph_model.gd")
    overlay = read("scripts/notes/note_workspace_overlay.gd")
    fallback = read("scripts/localization/core_ru_fallback.gd")
    require("textual_relation_count" in model and "explicit_relation_count" in model, "graph provenance counters are missing")
    require("notes.graph.stats_split" in overlay, "Notes graph toolbar still mixes relation classes")
    require("Текстовых связей" in fallback and "Графовых связей" in fallback, "RU fallback does not distinguish graph relation classes")
    smoke = read("tools/notes_core_smoke_test.gd")
    require('relation_counts.get("textual"' in smoke and 'relation_counts.get("explicit"' in smoke, "graph provenance counts lack runtime assertions")


def test_runtime_scope() -> None:
    runtime = read("tools/stage11_9_runtime_smoke_test.gd")
    for marker in (
        "_test_folder_tree_runtime",
        "_test_note_media_embed_runtime",
        "missing SHA embed",
        "_test_portable_note_embed_roundtrip",
        "Notes+embeds ON",
        "embeds OFF",
    ):
        require(marker in runtime, f"Stage 11.9 runtime smoke lost scope marker: {marker}")
    stub = read("tools/fixtures/stage11_9_board_repository_stub.gd")
    require("avoids" in stub and "BoardRepository.ROOT_DIR" in stub, "runtime portable smoke no longer documents user-data isolation")


def main() -> None:
    test_tree_reentrancy_boundary()
    test_schema_aware_asset_remap()
    test_board_independent_module_host()
    test_graph_provenance_stats()
    test_runtime_scope()
    print("Stage 11.9 architecture/runtime hardening contract passed.")


if __name__ == "__main__":
    main()
