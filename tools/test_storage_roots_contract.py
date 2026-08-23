from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def test_settings_persist_three_storage_roots() -> None:
    text = read("scripts/settings/app_settings_store.gd")
    for term in (
        "const SETTINGS_SCHEMA_VERSION: int = 19",
        'const DEFAULT_BOARD_ROOT: String = "user://notlight"',
        "var board_root: String = DEFAULT_BOARD_ROOT",
        '"board_root": board_root',
        "func set_board_root(value: String) -> void:",
        'if source_version < 19 and not migrated.has("board_root"):',
    ):
        assert term in text


def test_all_three_storage_services_support_exact_roots_and_safe_adoption() -> None:
    assets = read("scripts/assets/asset_library_service.gd")
    modules = read("scripts/modules/module_registry.gd")
    boards = read("scripts/data/board_repository.gd")
    assert 'leaf == "library" or leaf == "notlightlibrary"' in assets
    assert '"notlight/library"' in assets
    assert "_prepared_external_adopt_existing = true" in assets
    assert 'leaf == "modules" or leaf == "notlightmodules"' in modules
    assert '"notlight/modules"' in modules
    assert "_prepared_external_adopt_existing = true" in modules
    assert 'selected_abs.get_file().nocasecmp_to("boards") == 0' in boards
    assert 'for relative: String in ["notlight", "NotLightBoards"]' in boards
    assert "func prepare_external_boards" in boards


def test_legacy_notlight_board_userdata_is_detected_without_overwriting_current_data() -> None:
    app = read("scripts/app/app_root.gd")
    assert 'path_join("NotLight Board").path_join("notlight")' in app
    assert "not _board_storage_has_user_data(current_board_root)" in app
    assert "not _library_storage_has_user_data(current_library_root)" in app
    assert "not _module_storage_has_user_data(current_module_root)" in app
    assert "settings.set_board_root(legacy_board_root)" in app
    assert "settings.set_library_root(legacy_library_root)" in app
    assert "settings.set_module_root(legacy_module_root)" in app


def test_storage_ui_exposes_boards_resources_modules_and_uses_godot_folder_picker() -> None:
    ui = read("scripts/ui/settings_dialog.gd")
    for term in (
        "STORAGE_TARGET_BOARDS",
        'NotLightL10n.text("settings.storage.boards")',
        "_choose_board_location",
        "_open_board_folder",
        "repository.prepare_external_boards(path)",
        "_folder_dialog.use_native_dialog = false",
    ):
        assert term in ui


def test_clean_shutdown_commits_all_three_roots_atomically() -> None:
    app = read("scripts/app/app_root.gd")
    for term in (
        "repository.finalize_prepared_external_boards()",
        "asset_library.finalize_prepared_external_library()",
        "module_registry.finalize_prepared_external_modules()",
        "settings.set_board_root(prepared_board_root)",
        "settings.set_library_root(prepared_library_root)",
        "settings.set_module_root(prepared_module_root)",
        "repository.mark_prepared_external_boards_activated()",
    ):
        assert term in app


def test_portable_package_uses_configured_board_root() -> None:
    text = read("scripts/portable/notlight_portable_package_service.gd")
    assert "repository.get_root_directory()" in text
    assert "PackedStringArray([BoardRepository.ROOT_DIR" not in text


def test_windows_build_executes_real_storage_roots_smoke_test() -> None:
    text = read("tools/build_windows.ps1")
    assert 'tools\\storage_roots_smoke_test.gd' in text
    assert '"--script", "res://tools/storage_roots_smoke_test.gd"' in text
    assert 'Storage-roots migration smoke test passed.' in text


def test_board_screen_passes_board_repository_to_storage_settings() -> None:
    board = read("scripts/ui/board_screen.gd")
    app = read("scripts/app/app_root.gd")
    assert "var repository: BoardRepository" in board
    assert "board_repository_service: BoardRepository = null" in board
    assert "repository = board_repository_service" in board
    assert "_settings_dialog.configure(settings, asset_library, video_media, false, module_registry, app_audio, repository)" in board
    assert "board_screen.configure(session, settings, asset_library, image_cache, pdf_media, video_media, audio_media, voice_recording, telemetry, pdf_optimizer, formula_render, power_status, module_registry, note_repository, app_audio, repository)" in app


def test_windows_build_fails_on_godot_script_errors_even_with_zero_exit_code() -> None:
    text = read("tools/build_windows.ps1")
    assert "function Invoke-GodotChecked" in text
    assert "SCRIPT ERROR:" in text
    assert "Parse Error:" in text
    assert "Failed to load script" in text


def test_storage_moves_delete_old_sources_only_after_verified_switch() -> None:
    assets = read("scripts/assets/asset_library_service.gd")
    modules = read("scripts/modules/module_registry.gd")
    boards = read("scripts/data/board_repository.gd")
    app = read("scripts/app/app_root.gd")
    assert "func cleanup_migrated_external_library_source() -> Dictionary:" in assets
    assert "func cleanup_migrated_external_modules_source() -> Dictionary:" in modules
    assert "func cleanup_migrated_external_board_source() -> Dictionary:" in boards
    assert "settings.flush_pending_save()" in app
    assert "repository.cleanup_migrated_external_board_source()" in app
    assert "asset_library.cleanup_migrated_external_library_source()" in app
    assert "module_registry.cleanup_migrated_external_modules_source()" in app


def test_initialized_empty_destinations_are_replaceable() -> None:
    assets = read("scripts/assets/asset_library_service.gd")
    modules = read("scripts/modules/module_registry.gd")
    boards = read("scripts/data/board_repository.gd")
    assert "destination_has_content: bool = _library_has_content(destination)" in assets
    assert "if not destination_has_content:" in assets
    assert "destination_has_content: bool = _module_storage_has_content(destination)" in modules
    assert "destination_has_content: bool = _board_storage_has_content(destination)" in boards


def test_resource_smoke_test_moves_a_real_blob_and_reopens_it() -> None:
    smoke = read("tools/storage_roots_smoke_test.gd")
    for term in (
        "func _seed_real_resource",
        'blobs.call("commit_temp"',
        'library.call("register_managed_asset"',
        "func _assert_resource_reopens",
        "legacy Resource Library move into initialized empty target failed",
        "legacy Resource Library still exists after a successful move",
    ):
        assert term in smoke


def test_board_cleanup_preserves_legacy_library_and_module_siblings() -> None:
    boards = read("scripts/data/board_repository.gd")
    smoke = read("tools/storage_roots_smoke_test.gd")
    assert 'var source_boards: String = source_root.path_join("boards")' in boards
    assert 'for index_name: String in ["index.json", "index.json.bak", "index.json.tmp"]' in boards
    assert "board migration deleted sibling legacy library data" in smoke
