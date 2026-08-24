# SPDX-License-Identifier: GPL-3.0-or-later
class_name ModuleRegistry
extends Node

signal modules_changed
signal module_load_failed(module_id: String, message: String)

const ROOT_DIR: String = "user://notlight/modules"
const STATE_FILE: String = "state.json"
const VERSIONS_DIR: String = "versions"
const VERSION_MANIFEST_FILE: String = "manifest.json"
const INSTALL_METADATA_FILE: String = "install.json"
const STATE_SCHEMA: String = "notlight.module_install_state"
const STATE_SCHEMA_VERSION: int = 1
const LEGACY_LOCALIZATION_ACTIVATION_ERROR_SHA256: String = "c7e157d2ddf81a6857337da2bd95175f5036dfa24e0ccd58275b7cec588ca965"
const REQUIRED_ENTRY_METHODS: Array[String] = [
	"notlight_get_default_state",
	"notlight_normalize_state",
	"notlight_create_surface",
]

var repository: BoardRepository
var _states: Dictionary = {}
var _entries: Dictionary = {}
var _active_manifests: Dictionary = {}
var _localization_bundles: Dictionary = {}
var _catalog_localization_bundles: Dictionary = {}
var _last_error: String = ""
var _root_dir: String = ROOT_DIR
var _prepared_external_root: String = ""
var _prepared_external_fingerprint: String = ""
var _prepared_external_adopt_existing: bool = false


func configure(board_repository: BoardRepository, module_root: String = ROOT_DIR) -> void:
	repository = board_repository
	_root_dir = module_root.strip_edges()
	if _root_dir.is_empty():
		_root_dir = ROOT_DIR


func setup() -> bool:
	_last_error = ""
	_entries.clear()
	_active_manifests.clear()
	_localization_bundles.clear()
	_catalog_localization_bundles.clear()
	_states.clear()
	if not _ensure_directory(_root_dir):
		return false
	_process_pending_removals()
	_scan_states()
	_recover_legacy_first_install_retry_state()
	_activate_installed_modules()
	modules_changed.emit()
	return true


func refresh_catalog() -> void:
	_catalog_localization_bundles.clear()
	_scan_states()
	modules_changed.emit()


func get_last_error() -> String:
	return _last_error


func is_module_active(module_id: String) -> bool:
	return _entries.has(module_id.strip_edges().to_lower())


func get_active_manifest(module_id: String) -> Dictionary:
	var clean_id: String = module_id.strip_edges().to_lower()
	var value: Variant = _active_manifests.get(clean_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func module_text(module_id: String, key: String, locale: String, values: Dictionary = {}) -> String:
	var clean_id: String = module_id.strip_edges().to_lower()
	var clean_key: String = key.strip_edges()
	var clean_locale: String = _normalize_locale(locale)
	var translated: String = _lookup_module_text(clean_id, clean_key, clean_locale)
	if translated.is_empty() and clean_locale != "ru":
		translated = _lookup_module_text(clean_id, clean_key, "ru")
	if translated.is_empty():
		translated = clean_key
	return translated.format(values) if not values.is_empty() else translated


func get_known_module_info(module_id: String) -> Dictionary:
	var clean_id: String = module_id.strip_edges().to_lower()
	var state_value: Variant = _states.get(clean_id, {})
	if state_value is not Dictionary:
		return {}
	return _build_info(clean_id, state_value as Dictionary)


func list_modules() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var keys: Array = _states.keys()
	keys.sort()
	for raw_id: Variant in keys:
		var module_id: String = str(raw_id)
		result.append(_build_info(module_id, _states[module_id] as Dictionary))
	return result


func default_state(module_id: String) -> Dictionary:
	var entry: Object = _entry(module_id)
	if entry == null:
		return {}
	var raw: Variant = entry.call("notlight_get_default_state")
	if raw is not Dictionary:
		return {}
	var normalized: Dictionary = normalize_state(module_id, raw as Dictionary)
	if not bool(normalized.get("ok", false)):
		return {}
	var state_value: Variant = normalized.get("state", {})
	return (state_value as Dictionary).duplicate(true) if state_value is Dictionary else {}


func normalize_state(module_id: String, source: Dictionary) -> Dictionary:
	var clean_id: String = module_id.strip_edges().to_lower()
	var entry: Object = _entry(clean_id)
	if entry == null:
		return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.09801dbf2c")}
	var raw: Variant = entry.call("notlight_normalize_state", source.duplicate(true))
	if raw is not Dictionary:
		return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.01f910b68d")}
	var bounded: Dictionary = ModuleStore.normalize_state(raw as Dictionary)
	if not bool(bounded.get("ok", false)):
		return bounded
	return {"ok": true, "state": (bounded.get("state", {}) as Dictionary).duplicate(true)}


func create_surface(module_id: String) -> Control:
	var entry: Object = _entry(module_id)
	if entry == null:
		return null
	var raw: Variant = entry.call("notlight_create_surface")
	return raw as Control if raw is Control else null


func get_state_schema_version(module_id: String) -> int:
	var manifest: Dictionary = get_active_manifest(module_id)
	return int(manifest.get("state_schema_version", 0))


func request_remove(module_id: String) -> bool:
	var clean_id: String = module_id.strip_edges().to_lower()
	var state: Dictionary = _state_for(clean_id)
	if state.is_empty():
		_fail(NotLightL10n.text("runtime.modules.module_registry.b883bd985d"))
		return false
	state["pending_remove"] = true
	state["pending_version_key"] = ""
	if not _write_state(clean_id, state):
		return false
	_states[clean_id] = state
	modules_changed.emit()
	return true


func cancel_pending_remove(module_id: String) -> bool:
	var clean_id: String = module_id.strip_edges().to_lower()
	var state: Dictionary = _state_for(clean_id)
	if state.is_empty():
		return false
	state["pending_remove"] = false
	if not _write_state(clean_id, state):
		return false
	_states[clean_id] = state
	modules_changed.emit()
	return true


func write_install_state(module_id: String, state: Dictionary) -> bool:
	var clean_id: String = module_id.strip_edges().to_lower()
	if not ModuleManifest.is_valid_module_id(clean_id):
		_fail(NotLightL10n.text("runtime.modules.module_registry.95bf062b03"))
		return false
	var normalized: Dictionary = _normalize_state(clean_id, state)
	if not _write_state(clean_id, normalized):
		return false
	_states[clean_id] = normalized
	modules_changed.emit()
	return true


func get_root_directory() -> String:
	return _root_dir


func get_staging_directory() -> String:
	return _root_dir.path_join(".staging")


func prepare_external_modules(selected_directory: String) -> Dictionary:
	var selected: String = selected_directory.strip_edges()
	if selected.is_empty():
		return {"ok": false, "error": NotLightL10n.text("settings.storage.prepare_modules_failed")}
	if selected.begins_with("res://") or selected.begins_with("user://"):
		selected = ProjectSettings.globalize_path(selected)
	var selected_abs: String = selected.simplify_path()
	if not DirAccess.dir_exists_absolute(selected_abs):
		return {"ok": false, "error": NotLightL10n.text("settings.storage.folder_missing") % selected_abs}
	var source_root: String = ProjectSettings.globalize_path(_root_dir).simplify_path()
	var destination: String = _resolve_external_module_destination(selected_abs, source_root)
	if _storage_path_key(destination) == _storage_path_key(source_root):
		_prepared_external_root = ""
		_prepared_external_fingerprint = ""
		_prepared_external_adopt_existing = false
		return {"ok": true, "root": destination, "existing": true, "same_location": true, "restart_required": false}
	if _path_is_inside(destination, source_root) or _path_is_inside(source_root, destination):
		return {"ok": false, "error": NotLightL10n.text("settings.storage.overlap_error")}
	var parent: String = destination.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent):
		return {"ok": false, "error": NotLightL10n.text("settings.storage.folder_missing") % parent}
	var writable_error: String = _probe_writable_directory(parent)
	if not writable_error.is_empty():
		return {"ok": false, "error": writable_error}
	var destination_should_be_replaced: bool = false
	if DirAccess.dir_exists_absolute(destination):
		if _directory_is_empty_absolute(destination):
			destination_should_be_replaced = true
		else:
			var destination_fingerprint: String = _directory_tree_fingerprint(destination, 0)
			if destination_fingerprint.is_empty():
				return {"ok": false, "error": NotLightL10n.text("settings.storage.existing_invalid") % destination}
			var source_has_content: bool = _module_storage_has_content(source_root)
			var destination_has_content: bool = _module_storage_has_content(destination)
			if not source_has_content:
				_prepared_external_root = destination
				_prepared_external_fingerprint = destination_fingerprint
				_prepared_external_adopt_existing = true
				return {"ok": true, "root": destination, "existing": true, "adopted": true, "restart_required": true}
			if not destination_has_content:
				destination_should_be_replaced = true
			elif _directory_tree_fingerprint(source_root, 0) != destination_fingerprint:
				return {"ok": false, "error": NotLightL10n.text("settings.storage.populated_conflict")}
			else:
				_prepared_external_root = destination
				_prepared_external_fingerprint = destination_fingerprint
				_prepared_external_adopt_existing = false
				return {"ok": true, "root": destination, "existing": true, "restart_required": true}
	if destination_should_be_replaced and DirAccess.dir_exists_absolute(destination):
		if not _delete_directory_recursive_absolute(destination):
			return {"ok": false, "error": NotLightL10n.text("settings.storage.prepare_modules_failed")}
	var token: String = AssetId.make_temporary_id("modules-stage")
	var staging: String = parent.path_join(".notlight_modules_staging_%s" % token)
	if DirAccess.dir_exists_absolute(staging):
		_delete_directory_recursive_absolute(staging)
	if DirAccess.make_dir_recursive_absolute(staging) != OK:
		return {"ok": false, "error": NotLightL10n.text("settings.storage.prepare_modules_failed")}
	var copy_result: Dictionary = _copy_directory_tree_verified(source_root, staging, 0)
	if not bool(copy_result.get("ok", false)):
		_delete_directory_recursive_absolute(staging)
		return copy_result
	if not _directory_trees_equal(source_root, staging, 0):
		_delete_directory_recursive_absolute(staging)
		return {"ok": false, "error": NotLightL10n.text("settings.storage.verify_failed") % destination}
	if DirAccess.rename_absolute(staging, destination) != OK:
		_delete_directory_recursive_absolute(staging)
		return {"ok": false, "error": NotLightL10n.text("settings.storage.prepare_modules_failed")}
	_prepared_external_root = destination
	_prepared_external_fingerprint = _directory_tree_fingerprint(destination, 0)
	_prepared_external_adopt_existing = false
	return {"ok": true, "root": destination, "existing": false, "restart_required": true, "copied_files": int(copy_result.get("files", 0)), "copied_bytes": int(copy_result.get("bytes", 0))}


func has_prepared_external_modules() -> bool:
	return not _prepared_external_root.is_empty()


func get_prepared_external_modules_root() -> String:
	return _prepared_external_root


func finalize_prepared_external_modules() -> Dictionary:
	if _prepared_external_root.is_empty():
		return {"ok": true, "root": "", "changed": false}
	var source_root: String = ProjectSettings.globalize_path(_root_dir).simplify_path()
	var destination: String = _prepared_external_root.simplify_path()
	if _storage_path_key(source_root) == _storage_path_key(destination):
		return {"ok": true, "root": destination, "changed": false}
	if not DirAccess.dir_exists_absolute(destination):
		return {"ok": false, "error": NotLightL10n.text("settings.storage.folder_missing") % destination}
	var current_fingerprint: String = _directory_tree_fingerprint(destination, 0)
	if current_fingerprint.is_empty():
		return {"ok": false, "error": NotLightL10n.text("settings.storage.existing_invalid") % destination}
	if not _prepared_external_fingerprint.is_empty() and current_fingerprint != _prepared_external_fingerprint:
		return {"ok": false, "error": NotLightL10n.text("settings.storage.destination_changed")}
	if _prepared_external_adopt_existing:
		return {
			"ok": true,
			"root": destination,
			"changed": true,
			"adopted": true,
			"proof": current_fingerprint,
		}
	var parent: String = destination.get_base_dir()
	var writable_error: String = _probe_writable_directory(parent)
	if not writable_error.is_empty():
		return {"ok": false, "error": writable_error}
	var token: String = AssetId.make_temporary_id("modules-finalize")
	var staging: String = parent.path_join(".notlight_modules_finalize_%s" % token)
	var backup: String = parent.path_join(".notlight_modules_previous_%s" % token)
	# Materialize the staging root before copying. An empty Module Library has no
	# copyable entries (the root-level .staging directory is intentionally ignored),
	# so _copy_directory_tree_verified() can legitimately copy zero entries and
	# otherwise leave `staging` nonexistent. Verification must compare two existing
	# directory roots even when both effective trees are empty.
	if DirAccess.dir_exists_absolute(staging):
		if not _delete_directory_recursive_absolute(staging):
			return {"ok": false, "error": NotLightL10n.text("settings.storage.prepare_modules_failed")}
	if DirAccess.make_dir_recursive_absolute(staging) != OK:
		return {"ok": false, "error": NotLightL10n.text("settings.storage.prepare_modules_failed")}
	var copy_result: Dictionary = _copy_directory_tree_verified(source_root, staging, 0)
	if not bool(copy_result.get("ok", false)):
		_delete_directory_recursive_absolute(staging)
		return copy_result
	if not _directory_trees_equal(source_root, staging, 0):
		_delete_directory_recursive_absolute(staging)
		return {"ok": false, "error": NotLightL10n.text("settings.storage.verify_failed") % destination}
	var had_destination: bool = DirAccess.dir_exists_absolute(destination)
	if had_destination and DirAccess.rename_absolute(destination, backup) != OK:
		_delete_directory_recursive_absolute(staging)
		return {"ok": false, "error": NotLightL10n.text("settings.storage.prepare_modules_failed")}
	if DirAccess.rename_absolute(staging, destination) != OK:
		if had_destination:
			DirAccess.rename_absolute(backup, destination)
		_delete_directory_recursive_absolute(staging)
		return {"ok": false, "error": NotLightL10n.text("settings.storage.prepare_modules_failed")}
	if not _directory_trees_equal(source_root, destination, 0):
		_delete_directory_recursive_absolute(destination)
		if had_destination:
			DirAccess.rename_absolute(backup, destination)
		return {"ok": false, "error": NotLightL10n.text("settings.storage.verify_failed") % destination}
	if had_destination:
		_delete_directory_recursive_absolute(backup)
	_prepared_external_fingerprint = _directory_tree_fingerprint(destination, 0)
	return {
		"ok": true,
		"root": destination,
		"changed": true,
		"proof": _prepared_external_fingerprint,
	}


func cleanup_migrated_external_modules_source() -> Dictionary:
	# Compatibility wrapper for the direct storage smoke test. The durable app path
	# calls cleanup_migrated_module_source() with persisted source/target/proof.
	if _prepared_external_root.is_empty() or _prepared_external_adopt_existing:
		return {"ok": true, "removed": false}
	var source_root: String = ProjectSettings.globalize_path(_root_dir).simplify_path()
	var destination: String = _prepared_external_root.simplify_path()
	var cleaned: bool = cleanup_migrated_module_source(
		source_root,
		destination,
		_prepared_external_fingerprint
	)
	return {
		"ok": cleaned,
		"removed": cleaned,
		"source": source_root,
		"error": "" if cleaned else NotLightL10n.text("settings.storage.cleanup_failed") % source_root,
	}


func cleanup_migrated_module_source(source_root: String, destination_root: String, expected_proof: String = "") -> bool:
	var source: String = _globalized_storage_root(source_root)
	var destination: String = _globalized_storage_root(destination_root)
	if source.is_empty() or destination.is_empty():
		return false
	if _storage_path_key(source) == _storage_path_key(destination):
		return true
	if _path_is_inside(destination, source) or _path_is_inside(source, destination):
		return false
	var destination_fingerprint: String = _directory_tree_fingerprint(destination, 0)
	if destination_fingerprint.is_empty():
		return false
	var proof: String = expected_proof.strip_edges().to_lower()
	if not proof.is_empty():
		if proof.length() != 64 or destination_fingerprint != proof:
			return false
	elif _directory_tree_fingerprint(source, 0) != destination_fingerprint:
		return false

	# Remove only Module Library-owned entries. Valid module IDs and .staging are
	# app-owned; unrelated sibling files in an unusual historical root are kept.
	if DirAccess.dir_exists_absolute(source):
		for entry: String in DirAccess.get_directories_at(source):
			if entry == ".staging" or ModuleManifest.is_valid_module_id(entry):
				if not _delete_directory_recursive_absolute(source.path_join(entry)):
					return false
		if _directory_is_empty_absolute(source):
			DirAccess.remove_absolute(source)
	if not DirAccess.dir_exists_absolute(source):
		return true
	for entry: String in DirAccess.get_directories_at(source):
		if entry == ".staging" or ModuleManifest.is_valid_module_id(entry):
			return false
	return true


func _globalized_storage_root(value: String) -> String:
	var clean: String = value.strip_edges()
	if clean.is_empty():
		return ""
	if clean.begins_with("user://") or clean.begins_with("res://"):
		clean = ProjectSettings.globalize_path(clean)
	return clean.simplify_path()


func mark_prepared_external_modules_activated() -> void:
	_prepared_external_root = ""
	_prepared_external_fingerprint = ""
	_prepared_external_adopt_existing = false


func state_snapshot(module_id: String) -> Dictionary:
	return _state_for(module_id.strip_edges().to_lower())


func version_directory(module_id: String, version_key: String) -> String:
	return _root_dir.path_join(module_id).path_join(VERSIONS_DIR).path_join(version_key)


func module_directory(module_id: String) -> String:
	return _root_dir.path_join(module_id)


func read_version_manifest(module_id: String, version_key: String) -> Dictionary:
	if not _is_safe_version_key(version_key):
		return {}
	return _read_json(version_directory(module_id, version_key).path_join(VERSION_MANIFEST_FILE))


func installed_version_keys(module_id: String) -> PackedStringArray:
	var versions_path: String = module_directory(module_id).path_join(VERSIONS_DIR)
	var absolute: String = ProjectSettings.globalize_path(versions_path)
	if not DirAccess.dir_exists_absolute(absolute):
		return PackedStringArray()
	var result: PackedStringArray = PackedStringArray()
	for entry: String in DirAccess.get_directories_at(versions_path):
		if _is_safe_version_key(entry):
			result.append(entry)
	result.sort()
	return result


func _recover_legacy_first_install_retry_state() -> void:
	# Stage 10.0 originally cleared the pending key after a localization bridge
	# failure even for a first install. Recover only that exact beta failure: the
	# user already trusted/installed this one version, and _mount_version() will
	# re-verify every durable hash before any executable code is mounted.
	for raw_id: Variant in _states.keys():
		var module_id: String = str(raw_id)
		var state: Dictionary = _states[module_id] as Dictionary
		if bool(state.get("pending_remove", false)):
			continue
		if not str(state.get("active_version_key", "")).is_empty() or not str(state.get("pending_version_key", "")).is_empty():
			continue
		if str(state.get("last_error", "")).sha256_text() != LEGACY_LOCALIZATION_ACTIVATION_ERROR_SHA256:
			continue
		var installed: PackedStringArray = installed_version_keys(module_id)
		if installed.size() != 1:
			continue
		var candidate: String = installed[0]
		var manifest: Dictionary = read_version_manifest(module_id, candidate)
		if manifest.is_empty() or str(manifest.get("module_id", "")).strip_edges().to_lower() != module_id:
			continue
		var recovered: Dictionary = state.duplicate(true)
		recovered["pending_version_key"] = candidate
		if _write_state(module_id, recovered):
			_states[module_id] = recovered


func _activate_installed_modules() -> void:
	for raw_id: Variant in _states.keys():
		var module_id: String = str(raw_id)
		var state: Dictionary = _states[module_id] as Dictionary
		if bool(state.get("pending_remove", false)):
			continue
		var pending_key: String = str(state.get("pending_version_key", ""))
		var active_key: String = str(state.get("active_version_key", ""))
		var target_key: String = pending_key if not pending_key.is_empty() else active_key
		if target_key.is_empty():
			continue
		var result: Dictionary = _mount_version(module_id, target_key)
		if bool(result.get("ok", false)):
			if not pending_key.is_empty():
				var promoted_state: Dictionary = state.duplicate(true)
				promoted_state["active_version_key"] = pending_key
				promoted_state["pending_version_key"] = ""
				promoted_state["last_error"] = ""
				if _write_state(module_id, promoted_state):
					state = promoted_state
				else:
					# The new code is already mounted for this process and Module API v1
					# deliberately has no hot-unmount. Keep the durable pending marker in
					# memory so the next restart retries the same verified candidate.
					state["last_error"] = NotLightL10n.text("runtime.modules.module_registry.e6611207df")
					module_load_failed.emit(module_id, str(state["last_error"]))
				_states[module_id] = state
			continue
		var message: String = str(result.get("error", NotLightL10n.text("runtime.modules.module_registry.60dabf9fa4")))
		state["last_error"] = message.left(1000)
		if not pending_key.is_empty() and not active_key.is_empty():
			# If an update fails after its PCK was mounted, Module API v1 has no safe
			# hot-unmount. Fall back to the previously active version on next restart.
			# A first installation has no previous version to fall back to, so keep its
			# verified pending key visible/retriable instead of orphaning the install.
			state["pending_version_key"] = ""
		_write_state(module_id, state)
		_states[module_id] = state
		module_load_failed.emit(module_id, message)


func _mount_version(module_id: String, version_key: String) -> Dictionary:
	var version_dir: String = version_directory(module_id, version_key)
	var manifest_path: String = version_dir.path_join(VERSION_MANIFEST_FILE)
	var install_path: String = version_dir.path_join(INSTALL_METADATA_FILE)
	var install: Dictionary = _read_json(install_path)
	if install.is_empty():
		return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.4584aa5ee8")}
	var expected_manifest_hash: String = str(install.get("module_manifest_sha256", "")).strip_edges().to_lower()
	if expected_manifest_hash.length() != 64 or FileAccess.get_sha256(manifest_path).to_lower() != expected_manifest_hash:
		return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.47b6b72a2f")}
	var manifest_source: Dictionary = _read_json(manifest_path)
	var validated: Dictionary = ModuleManifest.validate(manifest_source)
	if not bool(validated.get("ok", false)):
		return {"ok": false, "error": str(validated.get("error", NotLightL10n.text("runtime.modules.module_registry.0a2e859df8")))}
	var manifest: Dictionary = validated.get("manifest", {}) as Dictionary
	if str(manifest.get("module_id", "")) != module_id:
		return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.c49bae271e")}
	if str(manifest.get("kind", "")) != ModuleManifest.KIND_CODE:
		return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.01b927eb76")}
	var payload_path: String = version_dir.path_join("payload.pck")
	if not FileAccess.file_exists(payload_path):
		return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.eef6b1c9f9")}
	var expected_hash: String = str(install.get("payload_sha256", "")).strip_edges().to_lower()
	if expected_hash.length() != 64 or FileAccess.get_sha256(payload_path).to_lower() != expected_hash:
		return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.a698f5797e")}
	var support_error: String = _verify_installed_support_files(version_dir, manifest, install)
	if not support_error.is_empty():
		return {"ok": false, "error": support_error}
	# Module localization is host-owned canonical support data. Load it from the
	# hash-verified installed version before mounting executable code so Module API
	# activation does not depend on a second global-autoload registration path.
	var localization_result: Dictionary = _read_version_localizations(module_id, version_dir, manifest)
	if not bool(localization_result.get("ok", false)):
		return {"ok": false, "error": str(localization_result.get("error", NotLightL10n.text("runtime.modules.module_registry.873a78f91f")))}
	if not ProjectSettings.load_resource_pack(ProjectSettings.globalize_path(payload_path), false):
		return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.fc7e98cb90")}
	var entry_path: String = str(manifest.get("entry_point", ""))
	var resource: Resource = ResourceLoader.load(entry_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource is not Script:
		return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.628b75f84d")}
	var script: Script = resource as Script
	if not script.can_instantiate():
		return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.8d2057b6e1")}
	var entry_value: Variant = script.new()
	if entry_value is not Object:
		return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.152fa7fd4f")}
	var entry: Object = entry_value as Object
	for method_name: String in REQUIRED_ENTRY_METHODS:
		if not entry.has_method(method_name):
			return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.1afb1a8645") % method_name}
	var default_value: Variant = entry.call("notlight_get_default_state")
	if default_value is not Dictionary:
		return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.54715ba92f")}
	var normalized_value: Variant = entry.call("notlight_normalize_state", default_value as Dictionary)
	if normalized_value is not Dictionary:
		return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.ce7ef7af9f")}
	var bounded: Dictionary = ModuleStore.normalize_state(normalized_value as Dictionary)
	if not bool(bounded.get("ok", false)):
		return {"ok": false, "error": str(bounded.get("error", NotLightL10n.text("runtime.modules.module_registry.4dc2aabc3a")))}
	var bundles_value: Variant = localization_result.get("bundles", {})
	if bundles_value is not Dictionary:
		return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.a150c1f7f1")}
	_localization_bundles[module_id] = (bundles_value as Dictionary).duplicate(true)
	_entries[module_id] = entry
	_active_manifests[module_id] = manifest.duplicate(true)
	return {"ok": true}


func _verify_installed_support_files(version_dir: String, manifest: Dictionary, install: Dictionary) -> String:
	var digests_value: Variant = install.get("package_payloads", {})
	if digests_value is not Dictionary:
		return NotLightL10n.text("runtime.modules.module_registry.1934c18e93")
	var digests: Dictionary = digests_value as Dictionary
	var localizations: Dictionary = manifest.get("localizations", {}) as Dictionary
	for raw_locale: Variant in localizations.keys():
		var locale: String = str(raw_locale)
		var key: String = str(localizations[raw_locale])
		var error: String = _verify_installed_file(version_dir.path_join("localization/%s.json" % locale), digests, key)
		if not error.is_empty():
			return error
	var icon_key: String = str(manifest.get("icon_key", ""))
	if not icon_key.is_empty():
		var icon_error: String = _verify_installed_file(version_dir.path_join("icon.%s" % icon_key.get_extension().to_lower()), digests, icon_key)
		if not icon_error.is_empty():
			return icon_error
	var preview_key: String = str(manifest.get("preview_key", ""))
	if not preview_key.is_empty():
		var preview_error: String = _verify_installed_file(version_dir.path_join("preview.%s" % preview_key.get_extension().to_lower()), digests, preview_key)
		if not preview_error.is_empty():
			return preview_error
	var license_key: String = str(manifest.get("license_key", ""))
	if not license_key.is_empty():
		var license_error: String = _verify_installed_file(version_dir.path_join("LICENSE"), digests, license_key)
		if not license_error.is_empty():
			return license_error
	var notices_key: String = str(manifest.get("notices_key", ""))
	if not notices_key.is_empty():
		var notices_error: String = _verify_installed_file(version_dir.path_join("THIRD_PARTY_NOTICES.md"), digests, notices_key)
		if not notices_error.is_empty():
			return notices_error
	return ""


func _verify_installed_file(path: String, digests: Dictionary, package_key: String) -> String:
	var descriptor_value: Variant = digests.get(package_key, {})
	if descriptor_value is not Dictionary:
		return NotLightL10n.text("runtime.modules.module_registry.e56313bccb") % package_key
	if not FileAccess.file_exists(path):
		return NotLightL10n.text("runtime.modules.module_registry.2b3fb2d371") % package_key
	var descriptor: Dictionary = descriptor_value as Dictionary
	var expected_size: int = int(descriptor.get("byte_size", -1))
	var expected_hash: String = str(descriptor.get("sha256", "")).strip_edges().to_lower()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return NotLightL10n.text("runtime.modules.module_registry.dc73ba8b6f") % package_key
	var actual_size: int = int(file.get_length())
	file.close()
	if expected_size < 0 or expected_hash.length() != 64 or actual_size != expected_size or FileAccess.get_sha256(path).to_lower() != expected_hash:
		return NotLightL10n.text("runtime.modules.module_registry.801ace74d9") % package_key
	return ""


func _read_version_localizations(module_id: String, version_dir: String, manifest: Dictionary) -> Dictionary:
	var localizations: Dictionary = manifest.get("localizations", {}) as Dictionary
	if not localizations.has("ru"):
		return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.064472a8df")}
	var bundles: Dictionary = {}
	for locale: String in ModuleManifest.SUPPORTED_LOCALES:
		if not localizations.has(locale):
			continue
		var path: String = version_dir.path_join("localization/%s.json" % locale)
		var result: Dictionary = ModuleLocalizationBundle.read_file(path, module_id, locale, locale == "ru")
		if not bool(result.get("ok", false)):
			return result
		var strings_value: Variant = result.get("strings", {})
		if strings_value is not Dictionary:
			return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.f59b740c4c") % locale}
		bundles[locale] = (strings_value as Dictionary).duplicate(true)
	if not bundles.has("ru"):
		return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.24800ba1a2")}
	return {"ok": true, "bundles": bundles}


func _lookup_module_text(module_id: String, key: String, locale: String) -> String:
	var module_value: Variant = _localization_bundles.get(module_id, {})
	if module_value is not Dictionary:
		return ""
	var locale_value: Variant = (module_value as Dictionary).get(locale, {})
	if locale_value is not Dictionary:
		return ""
	return str((locale_value as Dictionary).get(key, ""))


func _normalize_locale(locale: String) -> String:
	var normalized: String = locale.strip_edges().to_lower().replace("-", "_")
	if normalized.contains("_"):
		normalized = normalized.get_slice("_", 0)
	return normalized if ModuleManifest.SUPPORTED_LOCALES.has(normalized) else "ru"


func _process_pending_removals() -> void:
	var absolute_root: String = ProjectSettings.globalize_path(_root_dir)
	if not DirAccess.dir_exists_absolute(absolute_root):
		return
	for entry: String in DirAccess.get_directories_at(_root_dir):
		if not ModuleManifest.is_valid_module_id(entry):
			continue
		var state: Dictionary = _read_json(module_directory(entry).path_join(STATE_FILE))
		if not bool(state.get("pending_remove", false)):
			continue
		if _delete_directory_recursive(module_directory(entry)):
			continue
		# Deletion is retried on the next startup. Keep the durable pending_remove
		# marker rather than pretending the module disappeared after a partial I/O
		# failure; this prevents activation from a half-removed version tree.
		state["last_error"] = NotLightL10n.text("runtime.modules.module_registry.6dd01e7de7")
		_write_state(entry, state)
		_fail(str(state["last_error"]))


func _scan_states() -> void:
	_states.clear()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_root_dir)):
		return
	for entry: String in DirAccess.get_directories_at(_root_dir):
		if not ModuleManifest.is_valid_module_id(entry):
			continue
		var source: Dictionary = _read_json(module_directory(entry).path_join(STATE_FILE))
		if source.is_empty():
			continue
		_states[entry] = _normalize_state(entry, source)


func _build_info(module_id: String, state: Dictionary) -> Dictionary:
	var active_key: String = str(state.get("active_version_key", ""))
	var pending_key: String = str(state.get("pending_version_key", ""))
	var display_key: String = pending_key if not pending_key.is_empty() else active_key
	var manifest: Dictionary = read_version_manifest(module_id, display_key) if not display_key.is_empty() else {}
	var usage: Array[Dictionary] = []
	if repository != null:
		usage = repository.list_boards_using_module(module_id)
	var version_dir: String = version_directory(module_id, display_key) if not display_key.is_empty() else ""
	var install: Dictionary = _read_json(version_dir.path_join(INSTALL_METADATA_FILE)) if not version_dir.is_empty() else {}
	var catalog_bundles: Dictionary = _catalog_localizations(module_id, display_key, version_dir, manifest, install)
	var locale: String = NotLightL10n.current_locale()
	var localized_name: String = ModuleLocalizationBundle.resolve_manifest_text(manifest, catalog_bundles, "name", locale)
	var localized_description: String = ModuleLocalizationBundle.resolve_manifest_text(manifest, catalog_bundles, "description", locale)
	if localized_name.is_empty():
		localized_name = module_id
	var icon_path: String = _installed_artwork_path(version_dir, str(manifest.get("icon_key", "")), "icon")
	var preview_path: String = _installed_artwork_path(version_dir, str(manifest.get("preview_key", "")), "preview")
	return {
		"module_id": module_id,
		"name": localized_name,
		"description": localized_description,
		"version": str(manifest.get("version", "")),
		"active_version_key": active_key,
		"pending_version_key": pending_key,
		"pending_remove": bool(state.get("pending_remove", false)),
		"restart_required": not pending_key.is_empty() or bool(state.get("pending_remove", false)),
		"active": _entries.has(module_id),
		"last_error": str(state.get("last_error", "")),
		"byte_size": _directory_size(module_directory(module_id)),
		"boards_used": usage,
		"boards_used_count": usage.size(),
		"capabilities": (manifest.get("capabilities", []) as Array).duplicate(true) if manifest.get("capabilities", []) is Array else [],
		"license": str(manifest.get("license", "")),
		"author": str(manifest.get("author", "")),
		"homepage": str(manifest.get("homepage", "")),
		"kind": str(manifest.get("kind", ModuleManifest.KIND_CODE)),
		"module_api_version": int(manifest.get("module_api_version", 0)),
		"godot_version": str(manifest.get("godot_version", "")),
		"state_schema_version": int(manifest.get("state_schema_version", 0)),
		"payload_byte_size": int(install.get("payload_byte_size", 0)),
		"payload_sha256": str(install.get("payload_sha256", "")),
		"source_package_sha256": str(install.get("source_package_sha256", "")),
		"installed_at_unix": int(install.get("installed_at_unix", 0)),
		"icon_path": icon_path,
		"preview_path": preview_path,
	}


func _catalog_localizations(
	module_id: String,
	version_key: String,
	version_dir: String,
	manifest: Dictionary,
	install: Dictionary
) -> Dictionary:
	if version_key.is_empty() or version_dir.is_empty() or manifest.is_empty() or install.is_empty():
		return {}
	var cache_key: String = "%s\n%s" % [module_id, version_key]
	var cached_value: Variant = _catalog_localization_bundles.get(cache_key)
	if cached_value is Dictionary:
		return (cached_value as Dictionary).duplicate(true)
	var manifest_path: String = version_dir.path_join(VERSION_MANIFEST_FILE)
	var expected_manifest_hash: String = str(install.get("module_manifest_sha256", "")).strip_edges().to_lower()
	if expected_manifest_hash.length() != 64 or FileAccess.get_sha256(manifest_path).to_lower() != expected_manifest_hash:
		return {}
	var validated: Dictionary = ModuleManifest.validate(manifest)
	if not bool(validated.get("ok", false)):
		return {}
	var normalized_manifest: Dictionary = validated.get("manifest", {}) as Dictionary
	if str(normalized_manifest.get("module_id", "")) != module_id:
		return {}
	var digests_value: Variant = install.get("package_payloads", {})
	if digests_value is not Dictionary:
		return {}
	var digests: Dictionary = digests_value as Dictionary
	var localizations: Dictionary = normalized_manifest.get("localizations", {}) as Dictionary
	for raw_locale: Variant in localizations.keys():
		var locale: String = str(raw_locale)
		var package_key: String = str(localizations[raw_locale])
		var path: String = version_dir.path_join("localization/%s.json" % locale)
		if not _verify_installed_file(path, digests, package_key).is_empty():
			return {}
	var result: Dictionary = _read_version_localizations(module_id, version_dir, normalized_manifest)
	if not bool(result.get("ok", false)):
		return {}
	var bundles_value: Variant = result.get("bundles", {})
	if bundles_value is not Dictionary:
		return {}
	var bundles: Dictionary = (bundles_value as Dictionary).duplicate(true)
	_catalog_localization_bundles[cache_key] = bundles.duplicate(true)
	return bundles


func _installed_artwork_path(version_dir: String, package_key: String, stem: String) -> String:
	if version_dir.is_empty() or package_key.is_empty():
		return ""
	var extension: String = package_key.get_extension().to_lower()
	if extension.is_empty():
		return ""
	var path: String = version_dir.path_join("%s.%s" % [stem, extension])
	return path if FileAccess.file_exists(path) else ""


func _entry(module_id: String) -> Object:
	var value: Variant = _entries.get(module_id.strip_edges().to_lower())
	return value as Object if value is Object else null


func _state_for(module_id: String) -> Dictionary:
	var value: Variant = _states.get(module_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _normalize_state(module_id: String, source: Dictionary) -> Dictionary:
	return {
		"schema": STATE_SCHEMA,
		"schema_version": STATE_SCHEMA_VERSION,
		"module_id": module_id,
		"active_version_key": str(source.get("active_version_key", "")) if _is_safe_version_key(str(source.get("active_version_key", ""))) else "",
		"pending_version_key": str(source.get("pending_version_key", "")) if _is_safe_version_key(str(source.get("pending_version_key", ""))) else "",
		"pending_remove": bool(source.get("pending_remove", false)),
		"last_error": str(source.get("last_error", "")).left(1000),
	}


func _resolve_external_module_destination(selected_abs: String, source_root: String) -> String:
	if _storage_path_key(selected_abs) == _storage_path_key(source_root):
		return selected_abs
	var leaf: String = selected_abs.get_file().to_lower()
	if leaf == "modules" or leaf == "notlightmodules" or _module_storage_has_content(selected_abs):
		return selected_abs
	for relative: String in ["modules", "NotLightModules", "notlight/modules"]:
		var candidate: String = selected_abs.path_join(relative).simplify_path()
		if DirAccess.dir_exists_absolute(candidate) and _module_storage_has_content(candidate):
			return candidate
	return selected_abs.path_join("NotLightModules").simplify_path()


func _module_storage_has_content(root: String) -> bool:
	if not DirAccess.dir_exists_absolute(root):
		return false
	for entry: String in DirAccess.get_directories_at(root):
		if entry.begins_with("."):
			continue
		var module_root: String = root.path_join(entry)
		if FileAccess.file_exists(module_root.path_join(STATE_FILE)) or DirAccess.dir_exists_absolute(module_root.path_join(VERSIONS_DIR)):
			return true
	return false


func _directory_is_empty_absolute(path: String) -> bool:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			directory.list_dir_end()
			return false
		entry = directory.get_next()
	directory.list_dir_end()
	return true


func _path_is_inside(candidate: String, parent: String) -> bool:
	var clean_candidate: String = _storage_path_key(candidate)
	var clean_parent: String = _storage_path_key(parent)
	if clean_candidate.is_empty() or clean_parent.is_empty():
		return false
	return clean_candidate == clean_parent or clean_candidate.begins_with(clean_parent + "/")


func _storage_path_key(path: String) -> String:
	var clean: String = path.simplify_path().replace("\\", "/").trim_suffix("/")
	return clean.to_lower() if OS.get_name() == "Windows" else clean


func _probe_writable_directory(path: String) -> String:
	var probe_path: String = path.path_join(".notlight_module_write_probe_%s.tmp" % AssetId.make_temporary_id("storage"))
	var probe: FileAccess = FileAccess.open(probe_path, FileAccess.WRITE)
	if probe == null:
		return NotLightL10n.text("runtime.modules.module_registry.b8136ba4cb")
	var payload: PackedByteArray = "NotLight module storage write probe".to_utf8_buffer()
	if not probe.store_buffer(payload):
		probe.close()
		DirAccess.remove_absolute(probe_path)
		return NotLightL10n.text("runtime.modules.module_registry.30c31bdf4b")
	probe.flush()
	var write_error: Error = probe.get_error()
	probe.close()
	if write_error != OK:
		DirAccess.remove_absolute(probe_path)
		return NotLightL10n.text("runtime.modules.module_registry.4478c68ad0")
	var readback: PackedByteArray = FileAccess.get_file_as_bytes(probe_path)
	DirAccess.remove_absolute(probe_path)
	return "" if readback == payload else NotLightL10n.text("runtime.modules.module_registry.16fb339654")


func _copy_directory_tree_verified(source: String, destination: String, depth: int) -> Dictionary:
	if depth > 64:
		return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.0383ef7efd")}
	var directory: DirAccess = DirAccess.open(source)
	if directory == null:
		return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.d359b3212c")}
	var files_copied: int = 0
	var bytes_copied: int = 0
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != ".." and not (depth == 0 and entry == ".staging"):
			var src: String = source.path_join(entry)
			var dst: String = destination.path_join(entry)
			if directory.is_link(entry):
				directory.list_dir_end()
				return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.21fbbe9d56") % entry}
			if directory.current_is_dir():
				if DirAccess.make_dir_recursive_absolute(dst) != OK:
					directory.list_dir_end()
					return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.db4181cdc0") % entry}
				var child: Dictionary = _copy_directory_tree_verified(src, dst, depth + 1)
				if not bool(child.get("ok", false)):
					directory.list_dir_end()
					return child
				files_copied += int(child.get("files", 0))
				bytes_copied += int(child.get("bytes", 0))
			else:
				if DirAccess.copy_absolute(src, dst) != OK or not _files_equal(src, dst):
					directory.list_dir_end()
					return {"ok": false, "error": NotLightL10n.text("runtime.modules.module_registry.d9ca2f9aa8") % entry}
				files_copied += 1
				var copied: FileAccess = FileAccess.open(dst, FileAccess.READ)
				if copied != null:
					bytes_copied += int(copied.get_length())
					copied.close()
		entry = directory.get_next()
	directory.list_dir_end()
	return {"ok": true, "files": files_copied, "bytes": bytes_copied}


func _directory_trees_equal(first_root: String, second_root: String, depth: int) -> bool:
	if depth > 64:
		return false
	var first: DirAccess = DirAccess.open(first_root)
	var second: DirAccess = DirAccess.open(second_root)
	if first == null or second == null:
		return false
	var first_entries: PackedStringArray = PackedStringArray()
	var second_entries: PackedStringArray = PackedStringArray()
	first.list_dir_begin()
	var entry: String = first.get_next()
	while not entry.is_empty():
		if entry != "." and entry != ".." and not (depth == 0 and entry == ".staging"):
			first_entries.append(entry)
		entry = first.get_next()
	first.list_dir_end()
	second.list_dir_begin()
	entry = second.get_next()
	while not entry.is_empty():
		if entry != "." and entry != ".." and not (depth == 0 and entry == ".staging"):
			second_entries.append(entry)
		entry = second.get_next()
	second.list_dir_end()
	first_entries.sort()
	second_entries.sort()
	if first_entries != second_entries:
		return false
	for child_name: String in first_entries:
		if first.is_link(child_name) or second.is_link(child_name):
			return false
		var first_path: String = first_root.path_join(child_name)
		var second_path: String = second_root.path_join(child_name)
		var first_is_dir: bool = DirAccess.dir_exists_absolute(first_path)
		var second_is_dir: bool = DirAccess.dir_exists_absolute(second_path)
		if first_is_dir != second_is_dir:
			return false
		if first_is_dir:
			if not _directory_trees_equal(first_path, second_path, depth + 1):
				return false
		elif not _files_equal(first_path, second_path):
			return false
	return true


func _directory_tree_fingerprint(root: String, depth: int) -> String:
	if depth > 64:
		return ""
	var directory: DirAccess = DirAccess.open(root)
	if directory == null:
		return ""
	var entries: PackedStringArray = PackedStringArray()
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != ".." and not (depth == 0 and entry == ".staging"):
			entries.append(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	entries.sort()
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	for child_name: String in entries:
		if directory.is_link(child_name):
			return ""
		var child_path: String = root.path_join(child_name)
		var is_directory: bool = DirAccess.dir_exists_absolute(child_path)
		var child_digest: String = ""
		if is_directory:
			child_digest = _directory_tree_fingerprint(child_path, depth + 1)
		else:
			child_digest = FileAccess.get_sha256(child_path).to_lower()
		if child_digest.length() != 64:
			return ""
		var row: String = "%s|%s|%s\\n" % ["d" if is_directory else "f", child_name, child_digest]
		if context.update(row.to_utf8_buffer()) != OK:
			return ""
	return context.finish().hex_encode()


func _files_equal(first_path: String, second_path: String) -> bool:
	var first: FileAccess = FileAccess.open(first_path, FileAccess.READ)
	if first == null:
		return false
	var second: FileAccess = FileAccess.open(second_path, FileAccess.READ)
	if second == null:
		first.close()
		return false
	if first.get_length() != second.get_length():
		first.close()
		second.close()
		return false
	const COMPARE_CHUNK: int = 256 * 1024
	while first.get_position() < first.get_length():
		var remaining: int = int(first.get_length() - first.get_position())
		var amount: int = mini(COMPARE_CHUNK, remaining)
		if first.get_buffer(amount) != second.get_buffer(amount):
			first.close()
			second.close()
			return false
	first.close()
	second.close()
	return true


func _delete_directory_recursive_absolute(path: String) -> bool:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return true
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child: String = path.path_join(entry)
			if directory.is_link(entry):
				if DirAccess.remove_absolute(child) != OK:
					directory.list_dir_end()
					return false
			elif directory.current_is_dir():
				if not _delete_directory_recursive_absolute(child):
					directory.list_dir_end()
					return false
			elif DirAccess.remove_absolute(child) != OK:
				directory.list_dir_end()
				return false
		entry = directory.get_next()
	directory.list_dir_end()
	return DirAccess.remove_absolute(path) == OK


func _write_state(module_id: String, state: Dictionary) -> bool:
	var module_dir: String = module_directory(module_id)
	if not _ensure_directory(module_dir):
		return false
	return _write_json_atomic(module_dir.path_join(STATE_FILE), _normalize_state(module_id, state))


func _write_json_atomic(path: String, data: Dictionary) -> bool:
	var temp: String = "%s.tmp" % path
	var backup: String = "%s.bak" % path
	if not _write_json_file(temp, data):
		return false
	_remove_file(backup)
	var had_original: bool = FileAccess.file_exists(path)
	if had_original and not _rename(path, backup):
		_remove_file(temp)
		return false
	if not _rename(temp, path):
		if had_original and FileAccess.file_exists(backup):
			_rename(backup, path)
		_remove_file(temp)
		return false
	_remove_file(backup)
	return true


func _write_json_file(path: String, data: Dictionary) -> bool:
	if not _ensure_directory(path.get_base_dir()):
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail(NotLightL10n.text("runtime.modules.module_registry.7e65460055"))
		return false
	var ok: bool = file.store_string(JSON.stringify(data, "  ", false, true))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if not ok or error != OK:
		_fail(NotLightL10n.text("runtime.modules.module_registry.a71e8a1767"))
		return false
	return true


func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _ensure_directory(path: String) -> bool:
	var absolute: String = ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(absolute):
		return true
	var error: Error = DirAccess.make_dir_recursive_absolute(absolute)
	if error != OK:
		_fail(NotLightL10n.text("runtime.modules.module_registry.c6f5fe7e13") % path)
		return false
	return true


func _rename(source: String, destination: String) -> bool:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(destination)) == OK


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _delete_directory_recursive(path: String) -> bool:
	var absolute: String = ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return true
	var directory: DirAccess = DirAccess.open(absolute)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child: String = path.path_join(entry)
			if directory.current_is_dir():
				if not _delete_directory_recursive(child):
					directory.list_dir_end()
					return false
			else:
				if DirAccess.remove_absolute(ProjectSettings.globalize_path(child)) != OK:
					directory.list_dir_end()
					return false
		entry = directory.get_next()
	directory.list_dir_end()
	return DirAccess.remove_absolute(absolute) == OK


func _directory_size(path: String) -> int:
	var absolute: String = ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return 0
	var directory: DirAccess = DirAccess.open(absolute)
	if directory == null:
		return 0
	var total: int = 0
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child: String = path.path_join(entry)
			if directory.current_is_dir():
				total += _directory_size(child)
			else:
				var file: FileAccess = FileAccess.open(child, FileAccess.READ)
				if file != null:
					total += int(file.get_length())
					file.close()
		entry = directory.get_next()
	directory.list_dir_end()
	return total


static func _is_safe_version_key(value: String) -> bool:
	var clean: String = value.strip_edges()
	return not clean.is_empty() and clean.get_file() == clean and not clean.contains("..") and not clean.contains("/") and not clean.contains("\\")


func _fail(message: String) -> void:
	_last_error = message
	push_error(message)
