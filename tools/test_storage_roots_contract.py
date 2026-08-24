from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def test_settings_persist_three_storage_roots_and_cleanup_markers() -> None:
    text = read("scripts/settings/app_settings_store.gd")
    for term in (
        "const SETTINGS_SCHEMA_VERSION: int = 20",
        'const DEFAULT_BOARD_ROOT: String = "user://notlight"',
        'const DEFAULT_LIBRARY_ROOT: String = "user://notlight/library"',
        'const DEFAULT_MODULE_ROOT: String = "user://notlight/modules"',
        "var board_root: String = DEFAULT_BOARD_ROOT",
        "var library_root: String = DEFAULT_LIBRARY_ROOT",
        "var module_root: String = DEFAULT_MODULE_ROOT",
        "var pending_storage_cleanup: Dictionary = {}",
        '"board_root": board_root',
        '"library_root": library_root',
        '"module_root": module_root',
        '"pending_storage_cleanup": pending_storage_cleanup.duplicate(true)',
        'if source_version < 19 and not migrated.has("board_root"):',
        'if source_version < 20 and not migrated.has("pending_storage_cleanup"):',
        "func begin_storage_migration(",
        "func restore_storage_migration_state(",
        "func complete_storage_migration(kind: String) -> void:",
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


def test_clean_shutdown_persists_verified_targets_before_deleting_old_sources() -> None:
    app = read("scripts/app/app_root.gd")
    for term in (
        "repository.finalize_prepared_external_boards()",
        "asset_library.finalize_prepared_external_library()",
        "module_registry.finalize_prepared_external_modules()",
        'settings.begin_storage_migration("boards"',
        'settings.begin_storage_migration("library"',
        'settings.begin_storage_migration("modules"',
        "if not activation_ok or not settings.flush_pending_save():",
        "repository.cleanup_migrated_board_source(",
        "asset_library.cleanup_migrated_library_source(",
        "module_registry.cleanup_migrated_module_source(",
        'settings.complete_storage_migration("boards")',
        'settings.complete_storage_migration("library")',
        'settings.complete_storage_migration("modules")',
        "_resume_pending_storage_cleanup()",
        "settings.restore_storage_migration_state(",
    ):
        assert term in app

    persist_pos = app.index('settings.begin_storage_migration("boards"')
    flush_pos = app.index("if not activation_ok or not settings.flush_pending_save():", persist_pos)
    cleanup_pos = app.index("repository.cleanup_migrated_board_source(", flush_pos)
    assert persist_pos < flush_pos < cleanup_pos


def test_close_request_waits_for_active_jobs_and_keeps_board_session_valid_until_exit() -> None:
    app = read("scripts/app/app_root.gd")
    for term in (
        "var _exit_requested: bool = false",
        "func _continue_application_exit() -> void:",
        "func _exit_wait_reason() -> String:",
        "func _schedule_exit_retry() -> void:",
        "asset_library.has_pending_imports()",
        "video_media.is_optimizing()",
        "session.save_now_sync()",
        "session.close_board(false)",
        "settings.settings_error.emit(clean_message)",
    ):
        assert term in app
    save_pos = app.index("session.save_now_sync()")
    finalize_pos = app.index("repository.finalize_prepared_external_boards()", save_pos)
    close_pos = app.index("session.close_board(false)", finalize_pos)
    quit_pos = app.index("get_tree().quit()", close_pos)
    assert save_pos < finalize_pos < close_pos < quit_pos


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


def test_storage_moves_have_restart_independent_verified_cleanup() -> None:
    assets = read("scripts/assets/asset_library_service.gd")
    modules = read("scripts/modules/module_registry.gd")
    boards = read("scripts/data/board_repository.gd")
    for text, term in (
        (boards, "func cleanup_migrated_board_source("),
        (assets, "func cleanup_migrated_library_source("),
        (modules, "func cleanup_migrated_module_source("),
    ):
        assert term in text
        assert 'expected_proof: String = ""' in text

    # Finalizers return a proof of the exact verified target snapshot. Cleanup is
    # allowed only after checking that proof, so a restart can safely retry using
    # the marker stored in settings.json rather than transient prepared state.
    assert '"proof": _prepared_external_fingerprint' in boards
    assert '"proof": _prepared_external_catalog_sha256' in assets
    assert '"proof": _prepared_external_fingerprint' in modules
    assert "_board_storage_fingerprint(destination) != proof" in boards
    assert "FileAccess.get_sha256(destination_catalog).to_lower() != proof" in assets
    assert "destination_fingerprint != proof" in modules


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

def test_zero_content_storage_finalizers_are_explicitly_safe() -> None:
    assets = read("scripts/assets/asset_library_service.gd")
    modules = read("scripts/modules/module_registry.gd")
    boards = read("scripts/data/board_repository.gd")
    smoke = read("tools/storage_roots_smoke_test.gd")

    # Module finalization must create the final staging root before copy/equality.
    module_finalize = modules.index("func finalize_prepared_external_modules() -> Dictionary:")
    module_staging = modules.index('var staging: String = parent.path_join(".notlight_modules_finalize_%s" % token)', module_finalize)
    module_mkdir = modules.index("DirAccess.make_dir_recursive_absolute(staging)", module_staging)
    module_copy = modules.index("var copy_result: Dictionary = _copy_directory_tree_verified(source_root, staging, 0)", module_staging)
    module_equal = modules.index("if not _directory_trees_equal(source_root, staging, 0):", module_copy)
    assert module_finalize < module_staging < module_mkdir < module_copy < module_equal

    # Resource finalization must not depend on directory enumeration order to
    # materialize the staging parent before catalog/file copies.
    resource_finalize = assets.index("func finalize_prepared_external_library() -> Dictionary:")
    resource_staging = assets.index('var staging: String = parent.path_join(".notlight_library_finalize_%s" % token)', resource_finalize)
    resource_mkdir = assets.index("DirAccess.make_dir_recursive_absolute(staging)", resource_staging)
    resource_copy = assets.index("var copy_result: Dictionary = _copy_directory_tree(source_root, staging)", resource_staging)
    assert resource_finalize < resource_staging < resource_mkdir < resource_copy

    # Board snapshot copying already creates both the storage root and the empty
    # boards directory explicitly, so zero-board moves never depend on child data.
    board_copy = boards.index("func _copy_board_storage_snapshot(source_root: String, destination_root: String) -> Dictionary:")
    board_root_mkdir = boards.index("DirAccess.make_dir_recursive_absolute(destination_root)", board_copy)
    board_dir_logic = boards.index('var destination_boards: String = destination_root.path_join("boards")', board_copy)
    assert board_copy < board_root_mkdir < board_dir_logic

    for term in (
        "zero-board repository finalize failed",
        "zero-board repository source cleanup rejected a verified migration",
        "zero-resource library finalize failed",
        "zero-resource library source cleanup rejected a verified migration",
        "empty Module Library finalize failed",
        "empty Module Library source still exists after a successful move",
    ):
        assert term in smoke
