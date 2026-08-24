# SPDX-License-Identifier: GPL-3.0-or-later
extends SceneTree

const BoardRepositoryScript: Script = preload("res://scripts/data/board_repository.gd")
const AssetLibraryServiceScript: Script = preload("res://scripts/assets/asset_library_service.gd")
const ModuleRegistryScript: Script = preload("res://scripts/modules/module_registry.gd")

var _failures: Array[String] = []


func _init() -> void:
	if not NotLightL10n.initialize():
		_fail("localization initialization failed: %s" % NotLightL10n.get_last_error())
	var token: String = "%d_%d" % [Time.get_ticks_msec(), randi()]
	var base_user: String = "user://storage-roots-smoke-%s" % token
	var base_abs: String = ProjectSettings.globalize_path(base_user).simplify_path()
	if DirAccess.make_dir_recursive_absolute(base_abs) != OK:
		_fail("could not create temporary smoke-test root: %s" % base_abs)
	else:
		_test_boards(base_abs)
		_test_resource_library(base_abs)
		_test_module_library(base_abs)
	_delete_directory_recursive_absolute(base_abs)
	if _failures.is_empty():
		print("Storage roots smoke test passed.")
		quit(0)
		return
	for message: String in _failures:
		push_error("Storage roots smoke test: %s" % message)
	quit(1)


func _test_boards(base_abs: String) -> void:
	var source: String = base_abs.path_join("board-source")
	DirAccess.make_dir_recursive_absolute(source)
	var repository: Node = BoardRepositoryScript.new()
	root.add_child(repository)
	if not bool(repository.call("setup", source)):
		_fail("board source setup failed: %s" % str(repository.call("get_last_error")))
		repository.queue_free()
		return
	var created_value: Variant = repository.call("create_board", "Storage smoke")
	var created: Dictionary = created_value as Dictionary if created_value is Dictionary else {}
	var board_id: String = str(created.get("id", ""))
	if board_id.is_empty():
		_fail("could not create board before migration")

	var parent: String = base_abs.path_join("board-parent")
	DirAccess.make_dir_recursive_absolute(parent)
	var prepared_value: Variant = repository.call("prepare_external_boards", parent)
	var prepared: Dictionary = prepared_value as Dictionary if prepared_value is Dictionary else {}
	var expected: String = parent.path_join("NotLightBoards").simplify_path()
	if not bool(prepared.get("ok", false)):
		_fail("board parent migration failed: %s" % str(prepared.get("error", "")))
	else:
		_assert_path(str(prepared.get("root", "")), expected, "board parent target")
		var finalized_value: Variant = repository.call("finalize_prepared_external_boards")
		var finalized: Dictionary = finalized_value as Dictionary if finalized_value is Dictionary else {}
		if not bool(finalized.get("ok", false)):
			_fail("board finalize failed: %s" % str(finalized.get("error", "")))
		else:
			_assert_path(str(finalized.get("root", "")), expected, "board finalized target")
			_assert_board_file(expected, board_id, "board target after finalize")
			var proof: String = str(finalized.get("proof", ""))
			if proof.length() != 64:
				_fail("board finalize did not return a durable cleanup proof")
			repository.call("mark_prepared_external_boards_activated")
			# Simulate the post-crash retry path: cleanup must not depend on the
			# in-memory prepared migration state that was just cleared.
			var cleanup_repository: Node = BoardRepositoryScript.new()
			root.add_child(cleanup_repository)
			if not bool(cleanup_repository.call("cleanup_migrated_board_source", source, expected, proof)):
				_fail("board source cleanup rejected a verified persisted migration")
			cleanup_repository.queue_free()
			if DirAccess.dir_exists_absolute(source.path_join("boards")):
				_fail("board migration left the old boards directory behind")

	# Regression: a board repository with zero boards must move into a brand-new
	# parent, finalize, return a durable proof, and clean up its old board-owned
	# storage without requiring any board package to exist.
	var no_board_source: String = base_abs.path_join("board-zero-content-source")
	DirAccess.make_dir_recursive_absolute(no_board_source)
	var no_board_repository: Node = BoardRepositoryScript.new()
	root.add_child(no_board_repository)
	if bool(no_board_repository.call("setup", no_board_source)):
		var no_board_parent: String = base_abs.path_join("board-zero-content-parent")
		DirAccess.make_dir_recursive_absolute(no_board_parent)
		var no_board_prepare_value: Variant = no_board_repository.call("prepare_external_boards", no_board_parent)
		var no_board_prepare: Dictionary = no_board_prepare_value as Dictionary if no_board_prepare_value is Dictionary else {}
		var no_board_target: String = no_board_parent.path_join("NotLightBoards").simplify_path()
		if not bool(no_board_prepare.get("ok", false)):
			_fail("zero-board repository prepare failed: %s" % str(no_board_prepare.get("error", "")))
		else:
			var no_board_finalize_value: Variant = no_board_repository.call("finalize_prepared_external_boards")
			var no_board_finalize: Dictionary = no_board_finalize_value as Dictionary if no_board_finalize_value is Dictionary else {}
			if not bool(no_board_finalize.get("ok", false)):
				_fail("zero-board repository finalize failed: %s" % str(no_board_finalize.get("error", "")))
			else:
				var no_board_proof: String = str(no_board_finalize.get("proof", ""))
				if no_board_proof.length() != 64:
					_fail("zero-board repository finalize did not return a durable cleanup proof")
				no_board_repository.call("mark_prepared_external_boards_activated")
				var no_board_cleanup: Node = BoardRepositoryScript.new()
				root.add_child(no_board_cleanup)
				if not bool(no_board_cleanup.call("cleanup_migrated_board_source", no_board_source, no_board_target, no_board_proof)):
					_fail("zero-board repository source cleanup rejected a verified migration")
				no_board_cleanup.queue_free()
				if DirAccess.dir_exists_absolute(no_board_source.path_join("boards")):
					_fail("zero-board repository left the old boards directory behind")
				if not DirAccess.dir_exists_absolute(no_board_target.path_join("boards")):
					_fail("zero-board repository migrated target is missing its boards directory")
				var no_board_reopen: Node = BoardRepositoryScript.new()
				root.add_child(no_board_reopen)
				if not bool(no_board_reopen.call("setup", no_board_target)):
					_fail("zero-board repository migrated target did not reopen")
				else:
					var no_boards_value: Variant = no_board_reopen.call("list_boards")
					if no_boards_value is Array and not (no_boards_value as Array).is_empty():
						_fail("zero-board repository gained boards during migration")
				no_board_reopen.queue_free()
	else:
		_fail("zero-board repository setup failed")
	no_board_repository.queue_free()

	# Historical board root can contain sibling resource/module stores. Migrating
	# boards must delete only board-owned paths, never those siblings.
	var legacy_root: String = base_abs.path_join("NotLight Board").path_join("notlight")
	if not _copy_directory_tree_absolute(expected, legacy_root):
		_fail("could not prepare legacy board root")
	DirAccess.make_dir_recursive_absolute(legacy_root.path_join("library"))
	var sibling_marker: String = legacy_root.path_join("library").path_join("keep.txt")
	_write_text_file(sibling_marker, "keep")

	var empty_source: String = base_abs.path_join("empty-board-source")
	DirAccess.make_dir_recursive_absolute(empty_source)
	var empty_repository: Node = BoardRepositoryScript.new()
	root.add_child(empty_repository)
	if bool(empty_repository.call("setup", empty_source)):
		var adopt_value: Variant = empty_repository.call("prepare_external_boards", legacy_root)
		var adopt: Dictionary = adopt_value as Dictionary if adopt_value is Dictionary else {}
		if not bool(adopt.get("ok", false)) or not bool(adopt.get("adopted", false)):
			_fail("legacy board root was not adoptable from an empty source: %s" % str(adopt.get("error", "")))
		else:
			var finalize_adopt_value: Variant = empty_repository.call("finalize_prepared_external_boards")
			var finalize_adopt: Dictionary = finalize_adopt_value as Dictionary if finalize_adopt_value is Dictionary else {}
			if not bool(finalize_adopt.get("ok", false)):
				_fail("legacy board adoption finalize failed: %s" % str(finalize_adopt.get("error", "")))
	empty_repository.queue_free()

	var legacy_active: Node = BoardRepositoryScript.new()
	root.add_child(legacy_active)
	if bool(legacy_active.call("setup", legacy_root)):
		var second_parent: String = base_abs.path_join("board-second-parent")
		var empty_target: String = second_parent.path_join("NotLightBoards")
		DirAccess.make_dir_recursive_absolute(empty_target.path_join("boards"))
		var move_value: Variant = legacy_active.call("prepare_external_boards", second_parent)
		var move_result: Dictionary = move_value as Dictionary if move_value is Dictionary else {}
		if not bool(move_result.get("ok", false)):
			_fail("board migration into an initialized empty target failed: %s" % str(move_result.get("error", "")))
		else:
			var move_finalize_value: Variant = legacy_active.call("finalize_prepared_external_boards")
			var move_finalize: Dictionary = move_finalize_value as Dictionary if move_finalize_value is Dictionary else {}
			if not bool(move_finalize.get("ok", false)):
				_fail("legacy board move finalize failed: %s" % str(move_finalize.get("error", "")))
			else:
				var move_proof: String = str(move_finalize.get("proof", ""))
				legacy_active.call("mark_prepared_external_boards_activated")
				var retry_repository: Node = BoardRepositoryScript.new()
				root.add_child(retry_repository)
				if not bool(retry_repository.call("cleanup_migrated_board_source", legacy_root, empty_target, move_proof)):
					_fail("legacy board source cleanup failed after prepared state was cleared")
				retry_repository.queue_free()
				_assert_board_file(empty_target, board_id, "board initialized-empty target")
				if not FileAccess.file_exists(sibling_marker):
					_fail("board migration deleted sibling legacy library data")
	else:
		_fail("could not reopen legacy board root")
	legacy_active.queue_free()
	repository.queue_free()


func _test_resource_library(base_abs: String) -> void:
	var board_root: String = base_abs.path_join("library-board-root")
	DirAccess.make_dir_recursive_absolute(board_root)
	var repository: Node = BoardRepositoryScript.new()
	root.add_child(repository)
	if not bool(repository.call("setup", board_root)):
		_fail("library test board repository setup failed")
		repository.queue_free()
		return

	# Regression: a Resource Library with zero user resources must move into a
	# brand-new parent, finalize, reopen empty, and remove its old app-owned store.
	var no_resource_source: String = base_abs.path_join("resource-zero-content-source")
	var no_resource_library: Node = AssetLibraryServiceScript.new()
	root.add_child(no_resource_library)
	if bool(no_resource_library.call("setup", repository, no_resource_source)):
		var no_resource_parent: String = base_abs.path_join("resource-zero-content-parent")
		DirAccess.make_dir_recursive_absolute(no_resource_parent)
		var no_resource_prepare_value: Variant = no_resource_library.call("prepare_external_library", no_resource_parent)
		var no_resource_prepare: Dictionary = no_resource_prepare_value as Dictionary if no_resource_prepare_value is Dictionary else {}
		var no_resource_target: String = no_resource_parent.path_join("NotLightLibrary").simplify_path()
		if not bool(no_resource_prepare.get("ok", false)):
			_fail("zero-resource library prepare failed: %s" % str(no_resource_prepare.get("error", "")))
		else:
			var no_resource_finalize_value: Variant = no_resource_library.call("finalize_prepared_external_library")
			var no_resource_finalize: Dictionary = no_resource_finalize_value as Dictionary if no_resource_finalize_value is Dictionary else {}
			if not bool(no_resource_finalize.get("ok", false)):
				_fail("zero-resource library finalize failed: %s" % str(no_resource_finalize.get("error", "")))
			else:
				var no_resource_proof: String = str(no_resource_finalize.get("proof", ""))
				if no_resource_proof.length() != 64:
					_fail("zero-resource library finalize did not return a durable cleanup proof")
				no_resource_library.call("mark_prepared_external_library_activated")
				var no_resource_cleanup: Node = AssetLibraryServiceScript.new()
				root.add_child(no_resource_cleanup)
				if not bool(no_resource_cleanup.call("cleanup_migrated_library_source", no_resource_source, no_resource_target, no_resource_proof)):
					_fail("zero-resource library source cleanup rejected a verified migration")
				no_resource_cleanup.queue_free()
				if DirAccess.dir_exists_absolute(no_resource_source):
					_fail("zero-resource library left the old source directory behind")
				var no_resource_reopen: Node = AssetLibraryServiceScript.new()
				root.add_child(no_resource_reopen)
				if not bool(no_resource_reopen.call("setup", repository, no_resource_target)):
					_fail("zero-resource library migrated target did not reopen")
				else:
					var no_resources_value: Variant = no_resource_reopen.call("list_assets")
					if no_resources_value is Array and not (no_resources_value as Array).is_empty():
						_fail("zero-resource library gained resources during migration")
				no_resource_reopen.queue_free()
	else:
		_fail("zero-resource library setup failed")
	no_resource_library.queue_free()

	var source: String = base_abs.path_join("resource-source")
	var library: Node = AssetLibraryServiceScript.new()
	root.add_child(library)
	if not bool(library.call("setup", repository, source)):
		_fail("resource source setup failed: %s" % str(library.call("get_last_error")))
		library.queue_free()
		repository.queue_free()
		return
	var seeded: Dictionary = _seed_real_resource(library)
	if seeded.is_empty():
		library.queue_free()
		repository.queue_free()
		return

	var parent: String = base_abs.path_join("resource-parent")
	DirAccess.make_dir_recursive_absolute(parent)
	var prepared_value: Variant = library.call("prepare_external_library", parent)
	var prepared: Dictionary = prepared_value as Dictionary if prepared_value is Dictionary else {}
	var expected: String = parent.path_join("NotLightLibrary").simplify_path()
	if not bool(prepared.get("ok", false)):
		_fail("resource parent migration failed: %s" % str(prepared.get("error", "")))
	else:
		_assert_path(str(prepared.get("root", "")), expected, "resource parent target")
		_assert_seeded_resource_files(expected, seeded, "resource target after prepare")
		var finalized_value: Variant = library.call("finalize_prepared_external_library")
		var finalized: Dictionary = finalized_value as Dictionary if finalized_value is Dictionary else {}
		if not bool(finalized.get("ok", false)):
			_fail("resource finalize failed: %s" % str(finalized.get("error", "")))
		else:
			_assert_seeded_resource_files(expected, seeded, "resource target after finalize")
			var proof: String = str(finalized.get("proof", ""))
			if proof.length() != 64:
				_fail("resource finalize did not return a durable cleanup proof")
			library.call("mark_prepared_external_library_activated")
			var cleanup_library: Node = AssetLibraryServiceScript.new()
			root.add_child(cleanup_library)
			if not bool(cleanup_library.call("cleanup_migrated_library_source", source, expected, proof)):
				_fail("resource source cleanup rejected a verified persisted migration")
			cleanup_library.queue_free()
			if DirAccess.dir_exists_absolute(source):
				_fail("resource migration left the old source library behind")
	_assert_resource_reopens(repository, expected, seeded, "resource migrated target reopen")

	# Exact reproduction of the reported user sequence:
	# 1. adopt .../NotLight Board/notlight/library;
	# 2. restart with that legacy root active;
	# 3. move it into another folder that already contains an initialized but
	#    empty NotLightLibrary shell.
	var old_notlight: String = base_abs.path_join("NotLight Board").path_join("notlight")
	var legacy_library: String = old_notlight.path_join("library")
	if not _copy_directory_tree_absolute(expected, legacy_library):
		_fail("could not prepare legacy resource library")

	var empty_source: String = base_abs.path_join("resource-empty-source")
	var empty_library: Node = AssetLibraryServiceScript.new()
	root.add_child(empty_library)
	if bool(empty_library.call("setup", repository, empty_source)):
		var adopt_value: Variant = empty_library.call("prepare_external_library", legacy_library)
		var adopt: Dictionary = adopt_value as Dictionary if adopt_value is Dictionary else {}
		if not bool(adopt.get("ok", false)) or not bool(adopt.get("adopted", false)):
			_fail("exact legacy resource library could not be adopted: %s" % str(adopt.get("error", "")))
		else:
			var adopt_finalize_value: Variant = empty_library.call("finalize_prepared_external_library")
			var adopt_finalize: Dictionary = adopt_finalize_value as Dictionary if adopt_finalize_value is Dictionary else {}
			if not bool(adopt_finalize.get("ok", false)):
				_fail("legacy resource adoption finalize failed: %s" % str(adopt_finalize.get("error", "")))
	else:
		_fail("empty resource library setup failed")
	empty_library.queue_free()

	var second_parent: String = base_abs.path_join("resource-second-parent")
	var empty_initialized_target: String = second_parent.path_join("NotLightLibrary")
	DirAccess.make_dir_recursive_absolute(second_parent)
	var target_shell: Node = AssetLibraryServiceScript.new()
	root.add_child(target_shell)
	if not bool(target_shell.call("setup", repository, empty_initialized_target)):
		_fail("could not initialize empty destination Resource Library")
	target_shell.queue_free()

	var legacy_active: Node = AssetLibraryServiceScript.new()
	root.add_child(legacy_active)
	if not bool(legacy_active.call("setup", repository, legacy_library)):
		_fail("could not reopen adopted legacy Resource Library")
	else:
		_assert_resource_available(legacy_active, seeded, "legacy active resource")
		var move_value: Variant = legacy_active.call("prepare_external_library", second_parent)
		var move_result: Dictionary = move_value as Dictionary if move_value is Dictionary else {}
		if not bool(move_result.get("ok", false)):
			_fail("legacy Resource Library move into initialized empty target failed: %s" % str(move_result.get("error", "")))
		else:
			_assert_path(str(move_result.get("root", "")), empty_initialized_target, "legacy resource move target")
			_assert_seeded_resource_files(empty_initialized_target, seeded, "legacy resource target after prepare")
			var move_finalize_value: Variant = legacy_active.call("finalize_prepared_external_library")
			var move_finalize: Dictionary = move_finalize_value as Dictionary if move_finalize_value is Dictionary else {}
			if not bool(move_finalize.get("ok", false)):
				_fail("legacy Resource Library finalize failed: %s" % str(move_finalize.get("error", "")))
			else:
				var move_proof: String = str(move_finalize.get("proof", ""))
				legacy_active.call("mark_prepared_external_library_activated")
				var retry_library: Node = AssetLibraryServiceScript.new()
				root.add_child(retry_library)
				if not bool(retry_library.call("cleanup_migrated_library_source", legacy_library, empty_initialized_target, move_proof)):
					_fail("legacy Resource Library cleanup failed after prepared state was cleared")
				retry_library.queue_free()
				if DirAccess.dir_exists_absolute(legacy_library):
					_fail("legacy Resource Library still exists after a successful move")
	legacy_active.queue_free()
	_assert_resource_reopens(repository, empty_initialized_target, seeded, "legacy Resource Library moved target reopen")
	library.queue_free()
	repository.queue_free()


func _test_module_library(base_abs: String) -> void:
	var board_root: String = base_abs.path_join("module-board-root")
	DirAccess.make_dir_recursive_absolute(board_root)
	var repository: Node = BoardRepositoryScript.new()
	root.add_child(repository)
	if not bool(repository.call("setup", board_root)):
		_fail("module test board repository setup failed")
		repository.queue_free()
		return
	var source: String = base_abs.path_join("module-source")
	DirAccess.make_dir_recursive_absolute(source)
	var registry: Node = ModuleRegistryScript.new()
	root.add_child(registry)
	registry.call("configure", repository, source)
	if not bool(registry.call("setup")):
		_fail("module source setup failed: %s" % str(registry.call("get_last_error")))
		registry.queue_free()
		repository.queue_free()
		return
	var sample_module_id: String = "notlight.storage-smoke-module"
	var sample_module: String = source.path_join(sample_module_id)
	DirAccess.make_dir_recursive_absolute(sample_module)
	_write_text_file(sample_module.path_join("state.json"), "{}")

	var parent: String = base_abs.path_join("module-parent")
	DirAccess.make_dir_recursive_absolute(parent)
	var prepared_value: Variant = registry.call("prepare_external_modules", parent)
	var prepared: Dictionary = prepared_value as Dictionary if prepared_value is Dictionary else {}
	var expected: String = parent.path_join("NotLightModules").simplify_path()
	if not bool(prepared.get("ok", false)):
		_fail("module parent migration failed: %s" % str(prepared.get("error", "")))
	else:
		var finalized_value: Variant = registry.call("finalize_prepared_external_modules")
		var finalized: Dictionary = finalized_value as Dictionary if finalized_value is Dictionary else {}
		if not bool(finalized.get("ok", false)):
			_fail("module finalize failed: %s" % str(finalized.get("error", "")))
		else:
			var proof: String = str(finalized.get("proof", ""))
			if proof.length() != 64:
				_fail("module finalize did not return a durable cleanup proof")
			registry.call("mark_prepared_external_modules_activated")
			var cleanup_registry: Node = ModuleRegistryScript.new()
			root.add_child(cleanup_registry)
			if not bool(cleanup_registry.call("cleanup_migrated_module_source", source, expected, proof)):
				_fail("module source cleanup rejected a verified persisted migration")
			cleanup_registry.queue_free()
			if DirAccess.dir_exists_absolute(source):
				_fail("module migration left the old source library behind")
	if not FileAccess.file_exists(expected.path_join(sample_module_id).path_join("state.json")):
		_fail("module marker missing after migration")

	# Regression: a completely empty Module Library must still finalize into a
	# fresh parent. The finalizer has to create its staging root explicitly because
	# there are zero copyable entries that could create it implicitly.
	var empty_finalize_source: String = base_abs.path_join("module-empty-finalize-source")
	DirAccess.make_dir_recursive_absolute(empty_finalize_source)
	var empty_finalize_registry: Node = ModuleRegistryScript.new()
	root.add_child(empty_finalize_registry)
	empty_finalize_registry.call("configure", repository, empty_finalize_source)
	if bool(empty_finalize_registry.call("setup")):
		var empty_finalize_parent: String = base_abs.path_join("module-empty-finalize-parent")
		DirAccess.make_dir_recursive_absolute(empty_finalize_parent)
		var empty_prepare_value: Variant = empty_finalize_registry.call("prepare_external_modules", empty_finalize_parent)
		var empty_prepare: Dictionary = empty_prepare_value as Dictionary if empty_prepare_value is Dictionary else {}
		var empty_target: String = empty_finalize_parent.path_join("NotLightModules").simplify_path()
		if not bool(empty_prepare.get("ok", false)):
			_fail("empty Module Library prepare failed: %s" % str(empty_prepare.get("error", "")))
		else:
			var empty_finalize_value: Variant = empty_finalize_registry.call("finalize_prepared_external_modules")
			var empty_finalize: Dictionary = empty_finalize_value as Dictionary if empty_finalize_value is Dictionary else {}
			if not bool(empty_finalize.get("ok", false)):
				_fail("empty Module Library finalize failed: %s" % str(empty_finalize.get("error", "")))
			else:
				var empty_proof: String = str(empty_finalize.get("proof", ""))
				if empty_proof.length() != 64:
					_fail("empty Module Library finalize did not return a durable cleanup proof")
				empty_finalize_registry.call("mark_prepared_external_modules_activated")
				var empty_cleanup_registry: Node = ModuleRegistryScript.new()
				root.add_child(empty_cleanup_registry)
				if not bool(empty_cleanup_registry.call("cleanup_migrated_module_source", empty_finalize_source, empty_target, empty_proof)):
					_fail("empty Module Library source cleanup rejected a verified migration")
				empty_cleanup_registry.queue_free()
				if DirAccess.dir_exists_absolute(empty_finalize_source):
					_fail("empty Module Library source still exists after a successful move")
				if not DirAccess.dir_exists_absolute(empty_target):
					_fail("empty Module Library migrated target is missing after finalize")
	else:
		_fail("empty Module Library registry setup failed")
	empty_finalize_registry.queue_free()

	var legacy_parent: String = base_abs.path_join("NotLight Board").path_join("notlight")
	var legacy_modules: String = legacy_parent.path_join("modules")
	if not _copy_directory_tree_absolute(expected, legacy_modules):
		_fail("could not prepare legacy module library")
	var empty_source: String = base_abs.path_join("module-empty-source")
	DirAccess.make_dir_recursive_absolute(empty_source)
	var empty_registry: Node = ModuleRegistryScript.new()
	root.add_child(empty_registry)
	empty_registry.call("configure", repository, empty_source)
	if bool(empty_registry.call("setup")):
		var exact_value: Variant = empty_registry.call("prepare_external_modules", legacy_modules)
		var exact: Dictionary = exact_value as Dictionary if exact_value is Dictionary else {}
		if not bool(exact.get("ok", false)) or not bool(exact.get("adopted", false)):
			_fail("exact legacy modules folder could not be adopted: %s" % str(exact.get("error", "")))
	else:
		_fail("empty module registry setup failed")
	empty_registry.queue_free()

	var legacy_active: Node = ModuleRegistryScript.new()
	root.add_child(legacy_active)
	legacy_active.call("configure", repository, legacy_modules)
	if bool(legacy_active.call("setup")):
		var second_parent: String = base_abs.path_join("module-second-parent")
		var target_shell: String = second_parent.path_join("NotLightModules")
		DirAccess.make_dir_recursive_absolute(target_shell.path_join(".staging"))
		var move_value: Variant = legacy_active.call("prepare_external_modules", second_parent)
		var move_result: Dictionary = move_value as Dictionary if move_value is Dictionary else {}
		if not bool(move_result.get("ok", false)):
			_fail("module move into initialized empty target failed: %s" % str(move_result.get("error", "")))
		else:
			var move_finalize_value: Variant = legacy_active.call("finalize_prepared_external_modules")
			var move_finalize: Dictionary = move_finalize_value as Dictionary if move_finalize_value is Dictionary else {}
			if not bool(move_finalize.get("ok", false)):
				_fail("legacy module move finalize failed: %s" % str(move_finalize.get("error", "")))
			else:
				var move_proof: String = str(move_finalize.get("proof", ""))
				legacy_active.call("mark_prepared_external_modules_activated")
				var retry_registry: Node = ModuleRegistryScript.new()
				root.add_child(retry_registry)
				if not bool(retry_registry.call("cleanup_migrated_module_source", legacy_modules, target_shell, move_proof)):
					_fail("legacy module cleanup failed after prepared state was cleared")
				retry_registry.queue_free()
				if DirAccess.dir_exists_absolute(legacy_modules):
					_fail("legacy module source still exists after a successful move")
				if not FileAccess.file_exists(target_shell.path_join(sample_module_id).path_join("state.json")):
					_fail("module marker missing in initialized-empty move target")
	else:
		_fail("could not reopen legacy module library")
	legacy_active.queue_free()
	registry.queue_free()
	repository.queue_free()


func _seed_real_resource(library: Node) -> Dictionary:
	var blobs: RefCounted = library.get("blobs") as RefCounted
	if blobs == null:
		_fail("resource blob store is unavailable")
		return {}
	var temp_path: String = str(blobs.call("make_temp_path", "storage-smoke-real-resource"))
	var payload: PackedByteArray = "NotLight storage migration real resource".to_utf8_buffer()
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		_fail("could not create a real resource blob")
		return {}
	file.store_buffer(payload)
	file.flush()
	file.close()
	var hash_sha256: String = FileAccess.get_sha256(temp_path).to_lower()
	var committed_value: Variant = blobs.call("commit_temp", temp_path, hash_sha256, "txt")
	var committed: Dictionary = committed_value as Dictionary if committed_value is Dictionary else {}
	var relative_path: String = str(committed.get("relative_path", ""))
	if relative_path.is_empty():
		_fail("could not commit a real resource blob")
		return {}
	var now: int = int(Time.get_unix_time_from_system())
	var asset_id: String = "storage-smoke-real-resource"
	var record: Dictionary = {
		"id": asset_id,
		"hash_sha256": hash_sha256,
		"blob_relpath": relative_path,
		"display_name": "Storage migration resource",
		"description": "",
		"tags": [],
		"original_filename": "storage-smoke.txt",
		"extension": "txt",
		"kind": 6,
		"byte_size": payload.size(),
		"folder_id": "",
		"created_at_unix": now,
		"imported_at_unix": now,
		"updated_at_unix": now,
		"metadata": {},
	}
	if not bool(library.call("register_managed_asset", record)):
		_fail("could not register a real resource in the catalog: %s" % str(library.call("get_last_error")))
		return {}
	return {"id": asset_id, "hash": hash_sha256, "relative": relative_path, "bytes": payload.size()}


func _assert_seeded_resource_files(root_path: String, seeded: Dictionary, label: String) -> void:
	var relative_path: String = str(seeded.get("relative", ""))
	var blob_path: String = root_path.path_join(relative_path)
	if not FileAccess.file_exists(root_path.path_join("catalog.json")):
		_fail("%s: catalog.json is missing" % label)
	if not FileAccess.file_exists(blob_path):
		_fail("%s: migrated blob is missing: %s" % [label, relative_path])
		return
	var expected_hash: String = str(seeded.get("hash", ""))
	if FileAccess.get_sha256(blob_path).to_lower() != expected_hash:
		_fail("%s: migrated blob hash differs" % label)


func _assert_resource_available(library: Node, seeded: Dictionary, label: String) -> void:
	var asset_id: String = str(seeded.get("id", ""))
	var asset_value: Variant = library.call("get_asset", asset_id)
	var asset: Dictionary = asset_value as Dictionary if asset_value is Dictionary else {}
	if asset.is_empty():
		_fail("%s: resource record is missing after reopening" % label)
		return
	var resolved: String = str(library.call("resolve_asset_path", asset_id))
	if resolved.is_empty() or not FileAccess.file_exists(resolved):
		_fail("%s: resource blob cannot be resolved after reopening" % label)
		return
	if FileAccess.get_sha256(resolved).to_lower() != str(seeded.get("hash", "")):
		_fail("%s: reopened resource blob hash differs" % label)


func _assert_resource_reopens(repository: Node, root_path: String, seeded: Dictionary, label: String) -> void:
	var reopened: Node = AssetLibraryServiceScript.new()
	root.add_child(reopened)
	if not bool(reopened.call("setup", repository, root_path)):
		_fail("%s: Resource Library could not reopen: %s" % [label, str(reopened.call("get_last_error"))])
	else:
		_assert_resource_available(reopened, seeded, label)
	reopened.queue_free()


func _assert_board_file(root_path: String, board_id: String, label: String) -> void:
	if board_id.is_empty():
		return
	var board_path: String = root_path.path_join("boards").path_join(board_id).path_join("board.json")
	if not FileAccess.file_exists(board_path):
		_fail("%s: board.json is missing" % label)


func _write_text_file(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("could not write smoke-test marker: %s" % path)
		return
	file.store_string(text)
	file.flush()
	file.close()


func _assert_path(actual: String, expected: String, label: String) -> void:
	var actual_key: String = actual.simplify_path().replace("\\", "/")
	var expected_key: String = expected.simplify_path().replace("\\", "/")
	if OS.get_name() == "Windows":
		actual_key = actual_key.to_lower()
		expected_key = expected_key.to_lower()
	if actual_key != expected_key:
		_fail("%s mismatch: expected %s, got %s" % [label, expected, actual])


func _copy_directory_tree_absolute(source: String, destination: String) -> bool:
	if DirAccess.dir_exists_absolute(destination):
		_delete_directory_recursive_absolute(destination)
	if DirAccess.make_dir_recursive_absolute(destination) != OK:
		return false
	var directory: DirAccess = DirAccess.open(source)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var src: String = source.path_join(entry)
			var dst: String = destination.path_join(entry)
			if directory.current_is_dir():
				if not _copy_directory_tree_absolute(src, dst):
					directory.list_dir_end()
					return false
			else:
				if DirAccess.copy_absolute(src, dst) != OK:
					directory.list_dir_end()
					return false
		entry = directory.get_next()
	directory.list_dir_end()
	return true


func _delete_directory_recursive_absolute(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		return true
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child: String = path.path_join(entry)
			if directory.current_is_dir():
				if not _delete_directory_recursive_absolute(child):
					directory.list_dir_end()
					return false
			else:
				if DirAccess.remove_absolute(child) != OK:
					directory.list_dir_end()
					return false
		entry = directory.get_next()
	directory.list_dir_end()
	return DirAccess.remove_absolute(path) == OK


func _fail(message: String) -> void:
	_failures.append(message)
