# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardRepository
extends Node

signal boards_changed
signal board_manifest_changed(metadata: Dictionary)
signal board_deleted(board_id: String)
signal repository_error(message: String)

const ROOT_DIR: String = "user://notlight"
const BOARDS_DIR: String = "user://notlight/boards"
const INDEX_PATH: String = "user://notlight/index.json"
const MANIFEST_FILE: String = "manifest.json"
const BOARD_FILE: String = "board.json"
const STROKE_PAYLOAD_PREFIX: String = "strokes_"
const INDEX_SCHEMA_VERSION: int = 1
const MANIFEST_SCHEMA_VERSION: int = 4

var _last_error: String = ""
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _root_dir: String = ROOT_DIR
var _boards_dir: String = BOARDS_DIR
var _index_path: String = INDEX_PATH
var _prepared_external_root: String = ""
var _prepared_external_fingerprint: String = ""
var _prepared_external_adopt_existing: bool = false


func setup(board_root: String = ROOT_DIR) -> bool:
	_clear_error()
	_rng.randomize()
	_root_dir = board_root.strip_edges()
	if _root_dir.is_empty():
		_root_dir = ROOT_DIR
	_boards_dir = _root_dir.path_join("boards")
	_index_path = _root_dir.path_join("index.json")
	var absolute_root: String = _absolute_path(_root_dir)
	var default_key: String = _storage_path_key(_absolute_path(ROOT_DIR))
	if _storage_path_key(absolute_root) != default_key and not DirAccess.dir_exists_absolute(absolute_root):
		_fail(NotLightL10n.text("runtime.data.board_repository.external_root_missing") % absolute_root)
		return false
	if not _ensure_directory(_root_dir):
		return false
	if not _ensure_directory(_boards_dir):
		return false
	return _rebuild_index_from_manifests()


func get_root_directory() -> String:
	return _root_dir


func get_last_error() -> String:
	return _last_error


func list_boards() -> Array[Dictionary]:
	_clear_error()
	var index: Dictionary = _read_supported_index()
	if index.is_empty():
		if not _rebuild_index_from_manifests():
			return []
		index = _read_supported_index()
	var result: Array[Dictionary] = []
	var raw_boards: Array = index.get("boards", []) as Array
	for item: Variant in raw_boards:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("updated_at_unix", 0)) > int(right.get("updated_at_unix", 0))
	)
	return result


func list_boards_using_module(module_id: String) -> Array[Dictionary]:
	var clean_module_id: String = module_id.strip_edges().to_lower()
	if not ModuleManifest.is_valid_module_id(clean_module_id):
		return []
	var result: Array[Dictionary] = []
	for metadata: Dictionary in list_boards():
		var refs_value: Variant = metadata.get("module_refs", [])
		if refs_value is not Array:
			continue
		var refs: Array = refs_value as Array
		if refs.has(clean_module_id):
			result.append(metadata.duplicate(true))
	return result


func create_board(board_name: String) -> Dictionary:
	_clear_error()
	var clean_name: String = board_name.strip_edges()
	if clean_name.is_empty():
		clean_name = NotLightL10n.text("hub.new_board")
	var board_id: String = _make_board_id()
	var board_dir: String = _board_dir(board_id)
	if not _ensure_board_directories(board_dir):
		return {}
	var now: int = int(Time.get_unix_time_from_system())
	var transaction_id: String = _make_transaction_id()
	var metadata: Dictionary = _make_metadata(board_id, clean_name, now, now, transaction_id, PackedStringArray(), PackedStringArray())
	var document: Dictionary = BoardDocumentSchema.make_empty()
	var storage: Dictionary = document.get("storage", {}) as Dictionary
	storage["transaction_id"] = transaction_id
	document["storage"] = storage
	if not _write_board_package_atomic(board_id, metadata, document, PackedByteArray()):
		_delete_directory_recursive(board_dir)
		return {}
	if not _upsert_index_metadata(metadata):
		# The board package is already durable. A damaged/stale index must never
		# make a successfully created board disappear, so rebuild from manifests
		# before reporting failure.
		if not _rebuild_index_from_manifests():
			return {}
		_clear_error()
	boards_changed.emit()
	board_manifest_changed.emit(metadata.duplicate(true))
	return metadata.duplicate(true)


func load_board(board_id: String) -> Dictionary:
	_clear_error()
	var safe_id: String = _safe_id(board_id)
	if safe_id.is_empty():
		_fail(NotLightL10n.text("runtime.data.board_repository.2944dd6f00"))
		return {}
	var pair: Dictionary = _read_consistent_board_pair(safe_id)
	if pair.is_empty():
		_fail(NotLightL10n.text("runtime.data.board_repository.9cfffca08e"))
		return {}
	var loaded: Dictionary = _materialize_board_pair(safe_id, pair)
	if not loaded.is_empty():
		return loaded
	# JSON may be intact while only the newest stroke sidecar was lost (power
	# loss, manual cleanup, interrupted sync). In that case prefer the previous
	# complete transaction instead of making the whole board unopenable.
	var backup_manifest: Dictionary = _read_json("%s.bak" % _manifest_path(safe_id), false)
	var backup_document: Dictionary = _read_json("%s.bak" % _board_path(safe_id), false)
	if _pair_is_consistent(backup_manifest, backup_document):
		loaded = _materialize_board_pair(safe_id, {"manifest": backup_manifest, "document": backup_document, "recovered": true})
		if not loaded.is_empty():
			return loaded
	_fail(NotLightL10n.text("runtime.data.board_repository.fbbbfb64ee"))
	return {}


func _materialize_board_pair(board_id: String, pair: Dictionary) -> Dictionary:
	var manifest_value: Variant = pair.get("manifest", {})
	var document_value: Variant = pair.get("document", {})
	if manifest_value is not Dictionary or document_value is not Dictionary:
		return {}
	var manifest: Dictionary = manifest_value as Dictionary
	var document: Dictionary = document_value as Dictionary
	if not BoardDocumentSchema.is_supported(document):
		return {}
	var normalized_document: Dictionary = BoardDocumentSchema.normalize(document)
	var stroke_payload: PackedByteArray = _read_stroke_payload(board_id, normalized_document)
	var content_value: Variant = normalized_document.get("content", {})
	if content_value is not Dictionary:
		return {}
	var content: Dictionary = content_value as Dictionary
	var strokes_value: Variant = content.get("strokes", [])
	if strokes_value is not Array:
		return {}
	var stroke_records: Array = strokes_value as Array
	if not stroke_records.is_empty() and stroke_payload.is_empty():
		return {}
	return {
		"metadata": _normalize_metadata(manifest, board_id),
		"document": normalized_document,
		"stroke_payload": stroke_payload,
		"recovered": bool(pair.get("recovered", false)),
	}


func save_board(board_id: String, metadata: Dictionary, document: Dictionary, stroke_payload: PackedByteArray = PackedByteArray()) -> Dictionary:
	_clear_error()
	var safe_id: String = _safe_id(board_id)
	if safe_id.is_empty():
		_fail(NotLightL10n.text("runtime.data.board_repository.2944dd6f00"))
		return {}
	if not _ensure_board_directories(_board_dir(safe_id)):
		return {}
	var old_manifest: Dictionary = _read_json(_manifest_path(safe_id), false)
	if old_manifest.is_empty():
		old_manifest = _read_json("%s.bak" % _manifest_path(safe_id), false)
	var now: int = int(Time.get_unix_time_from_system())
	var fallback_name: String = str(old_manifest.get("name", NotLightL10n.text("hub.new_board")))
	var clean_name: String = str(metadata.get("name", fallback_name)).strip_edges()
	if clean_name.is_empty():
		clean_name = NotLightL10n.text("hub.new_board")
	var created_at: int = int(metadata.get("created_at_unix", old_manifest.get("created_at_unix", now)))
	var transaction_id: String = _make_transaction_id()
	var clean_document: Dictionary = BoardDocumentSchema.normalize(document)
	var asset_refs: PackedStringArray = BoardDocumentSchema.collect_asset_references(clean_document)
	var module_refs: PackedStringArray = BoardDocumentSchema.collect_module_references(clean_document)
	var clean_metadata: Dictionary = _make_metadata(safe_id, clean_name, created_at, now, transaction_id, asset_refs, module_refs)
	var storage: Dictionary = clean_document.get("storage", {}) as Dictionary
	storage["transaction_id"] = transaction_id
	var clean_content: Dictionary = clean_document.get("content", {}) as Dictionary
	var stroke_records: Array = clean_content.get("strokes", []) as Array
	var payload_filename: String = ""
	if not stroke_records.is_empty():
		if stroke_payload.is_empty():
			_fail(NotLightL10n.text("runtime.data.board_repository.84ec4b611f"))
			return {}
		payload_filename = "%s%s.bin" % [STROKE_PAYLOAD_PREFIX, transaction_id]
		storage["stroke_payload"] = payload_filename
	else:
		storage["stroke_payload"] = ""
	clean_document["storage"] = storage
	if not _write_board_package_atomic(safe_id, clean_metadata, clean_document, stroke_payload):
		if not payload_filename.is_empty():
			_remove_file_if_exists(_board_dir(safe_id).path_join(payload_filename))
		return {}
	_cleanup_stale_stroke_payloads(safe_id, clean_document)
	if not _upsert_index_metadata(clean_metadata):
		# board.json + manifest.json were committed successfully; repair the
		# secondary Hub index instead of turning a durable save into a false loss.
		if not _rebuild_index_from_manifests():
			return {}
		_clear_error()
	boards_changed.emit()
	board_manifest_changed.emit(clean_metadata.duplicate(true))
	return clean_metadata.duplicate(true)


func duplicate_board(board_id: String, duplicate_name: String) -> Dictionary:
	_clear_error()
	var loaded: Dictionary = load_board(board_id)
	if loaded.is_empty():
		return {}
	var source_metadata: Dictionary = loaded.get("metadata", {}) as Dictionary
	var source_document: Dictionary = loaded.get("document", {}) as Dictionary
	var stroke_payload: PackedByteArray = PackedByteArray()
	var stroke_value: Variant = loaded.get("stroke_payload", PackedByteArray())
	if stroke_value is PackedByteArray:
		stroke_payload = stroke_value as PackedByteArray
	var now: int = int(Time.get_unix_time_from_system())
	var metadata: Dictionary = source_metadata.duplicate(true)
	metadata["id"] = ""
	metadata["name"] = duplicate_name.strip_edges()
	metadata["created_at_unix"] = now
	metadata["updated_at_unix"] = now
	if str(metadata.get("name", "")).is_empty():
		metadata["name"] = str(source_metadata.get("name", NotLightL10n.text("hub.new_board")))
	# import_board_snapshot always allocates a fresh board id when metadata.id is
	# empty and rewrites transactional storage metadata. The document is deep-
	# duplicated so subsequent edits are fully independent; global Library asset
	# and Note IDs remain shared references by design.
	return import_board_snapshot(metadata, source_document.duplicate(true), stroke_payload)


func rename_board(board_id: String, new_name: String) -> Dictionary:
	var loaded: Dictionary = load_board(board_id)
	if loaded.is_empty():
		return {}
	var metadata: Dictionary = loaded.get("metadata", {}) as Dictionary
	var document: Dictionary = loaded.get("document", {}) as Dictionary
	var stroke_payload: PackedByteArray = PackedByteArray()
	var stroke_payload_value: Variant = loaded.get("stroke_payload", PackedByteArray())
	if stroke_payload_value is PackedByteArray:
		stroke_payload = stroke_payload_value as PackedByteArray
	metadata["name"] = new_name.strip_edges()
	return save_board(board_id, metadata, document, stroke_payload)


func delete_board(board_id: String) -> bool:
	_clear_error()
	var safe_id: String = _safe_id(board_id)
	if safe_id.is_empty():
		_fail(NotLightL10n.text("runtime.data.board_repository.2944dd6f00"))
		return false
	var path: String = _board_dir(safe_id)
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		_fail(NotLightL10n.text("runtime.data.board_repository.653c2d76a0"))
		return false
	if not _delete_directory_recursive(path):
		return false
	if not _remove_index_metadata(safe_id):
		return false
	boards_changed.emit()
	board_deleted.emit(safe_id)
	return true


func make_empty_document() -> Dictionary:
	return BoardDocumentSchema.make_empty()


func get_board_directory(board_id: String) -> String:
	return _board_dir(_safe_id(board_id))


func contains_board(board_id: String) -> bool:
	var safe_id: String = _safe_id(board_id)
	if safe_id.is_empty():
		return false
	return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_board_dir(safe_id)))


func import_board_snapshot(metadata: Dictionary, document: Dictionary, stroke_payload: PackedByteArray = PackedByteArray()) -> Dictionary:
	_clear_error()
	if not BoardDocumentSchema.is_supported(document):
		_fail(NotLightL10n.text("runtime.data.board_repository.56396f4152"))
		return {}
	var raw_source_id: String = str(metadata.get("id", "")).strip_edges()
	var source_id: String = _safe_id(raw_source_id) if raw_source_id.length() <= 128 else ""
	var target_id: String = source_id
	if target_id.is_empty() or contains_board(target_id):
		target_id = _make_board_id()
		while contains_board(target_id):
			target_id = _make_board_id()
	var target_dir: String = _board_dir(target_id)
	if not _ensure_board_directories(target_dir):
		return {}
	var normalized_document: Dictionary = BoardDocumentSchema.normalize(document)
	var content: Dictionary = normalized_document.get("content", {}) as Dictionary
	var strokes: Array = content.get("strokes", []) as Array
	if not strokes.is_empty() and stroke_payload.is_empty():
		_delete_directory_recursive(target_dir)
		_fail(NotLightL10n.text("runtime.data.board_repository.777467d6d0"))
		return {}
	var now: int = int(Time.get_unix_time_from_system())
	var clean_name: String = str(metadata.get("name", NotLightL10n.text("hub.new_board"))).left(120).strip_edges()
	if clean_name.is_empty():
		clean_name = NotLightL10n.text("hub.new_board")
	var transaction_id: String = _make_transaction_id()
	var refs: PackedStringArray = BoardDocumentSchema.collect_asset_references(normalized_document)
	var module_refs: PackedStringArray = BoardDocumentSchema.collect_module_references(normalized_document)
	var created_at: int = maxi(0, int(metadata.get("created_at_unix", now)))
	var updated_at: int = maxi(0, int(metadata.get("updated_at_unix", now)))
	var imported_metadata: Dictionary = _make_metadata(
		target_id,
		clean_name,
		created_at,
		updated_at,
		transaction_id,
		refs,
		module_refs
	)
	var storage: Dictionary = normalized_document.get("storage", {}) as Dictionary
	storage["transaction_id"] = transaction_id
	if strokes.is_empty():
		storage["stroke_payload"] = ""
	else:
		storage["stroke_payload"] = "%s%s.bin" % [STROKE_PAYLOAD_PREFIX, transaction_id]
	normalized_document["storage"] = storage
	if not _write_board_package_atomic(target_id, imported_metadata, normalized_document, stroke_payload):
		_delete_directory_recursive(target_dir)
		return {}
	if not _upsert_index_metadata(imported_metadata):
		if not _rebuild_index_from_manifests():
			_delete_directory_recursive(target_dir)
			return {}
		_clear_error()
	boards_changed.emit()
	board_manifest_changed.emit(imported_metadata.duplicate(true))
	return imported_metadata.duplicate(true)



func prepare_external_boards(selected_directory: String) -> Dictionary:
	_clear_error()
	var selected: String = selected_directory.strip_edges()
	if selected.is_empty():
		return {"ok": false, "error": NotLightL10n.text("settings.storage.prepare_boards_failed")}
	var selected_abs: String = _absolute_path(selected).simplify_path()
	if not DirAccess.dir_exists_absolute(selected_abs):
		return {"ok": false, "error": NotLightL10n.text("settings.storage.folder_missing") % selected_abs}
	var source_root: String = _absolute_path(_root_dir).simplify_path()
	var destination: String = _resolve_external_board_destination(selected_abs, source_root)
	if _storage_path_key(destination) == _storage_path_key(source_root):
		_clear_prepared_external_boards()
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
			var validation: Dictionary = _validate_board_storage_snapshot(destination)
			if not bool(validation.get("ok", false)):
				return {"ok": false, "error": NotLightL10n.text("settings.storage.existing_invalid") % str(validation.get("error", ""))}
			var source_has_content: bool = _board_storage_has_content(source_root)
			var destination_has_content: bool = _board_storage_has_content(destination)
			if not source_has_content:
				_prepared_external_root = destination
				_prepared_external_fingerprint = _board_storage_fingerprint(destination)
				_prepared_external_adopt_existing = true
				return {"ok": true, "root": destination, "existing": true, "adopted": true, "restart_required": true}
			if not destination_has_content:
				destination_should_be_replaced = true
			elif _board_storage_fingerprint(source_root) != _board_storage_fingerprint(destination):
				return {"ok": false, "error": NotLightL10n.text("settings.storage.populated_conflict")}
			else:
				_prepared_external_root = destination
				_prepared_external_fingerprint = _board_storage_fingerprint(destination)
				_prepared_external_adopt_existing = false
				return {"ok": true, "root": destination, "existing": true, "restart_required": true}
	if destination_should_be_replaced and DirAccess.dir_exists_absolute(destination):
		if not _delete_directory_recursive(destination):
			return {"ok": false, "error": NotLightL10n.text("settings.storage.prepare_boards_failed")}

	var token: String = "%08x%08x" % [_rng.randi(), _rng.randi()]
	var staging: String = parent.path_join(".notlight_boards_staging_%s" % token)
	if DirAccess.dir_exists_absolute(staging):
		_delete_directory_recursive(staging)
	var copied: Dictionary = _copy_board_storage_snapshot(source_root, staging)
	if not bool(copied.get("ok", false)):
		_delete_directory_recursive(staging)
		return copied
	var validation: Dictionary = _validate_board_storage_snapshot(staging)
	if not bool(validation.get("ok", false)):
		_delete_directory_recursive(staging)
		return {"ok": false, "error": NotLightL10n.text("settings.storage.existing_invalid") % str(validation.get("error", ""))}
	if DirAccess.rename_absolute(staging, destination) != OK:
		_delete_directory_recursive(staging)
		return {"ok": false, "error": NotLightL10n.text("settings.storage.prepare_boards_failed")}
	_prepared_external_root = destination
	_prepared_external_fingerprint = _board_storage_fingerprint(destination)
	_prepared_external_adopt_existing = false
	return {
		"ok": true,
		"root": destination,
		"existing": false,
		"copied_files": int(copied.get("files", 0)),
		"copied_bytes": int(copied.get("bytes", 0)),
		"restart_required": true,
	}


func has_prepared_external_boards() -> bool:
	return not _prepared_external_root.is_empty()


func get_prepared_external_board_root() -> String:
	return _prepared_external_root


func finalize_prepared_external_boards() -> Dictionary:
	if _prepared_external_root.is_empty():
		return {"ok": true, "root": "", "changed": false}
	var source_root: String = _absolute_path(_root_dir).simplify_path()
	var destination: String = _prepared_external_root.simplify_path()
	if _storage_path_key(source_root) == _storage_path_key(destination):
		return {"ok": true, "root": destination, "changed": false}
	var current_validation: Dictionary = _validate_board_storage_snapshot(destination)
	if not bool(current_validation.get("ok", false)):
		return {"ok": false, "error": NotLightL10n.text("settings.storage.existing_invalid") % str(current_validation.get("error", ""))}
	var current_fingerprint: String = _board_storage_fingerprint(destination)
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
	var token: String = "%08x%08x" % [_rng.randi(), _rng.randi()]
	var staging: String = parent.path_join(".notlight_boards_finalize_%s" % token)
	var backup: String = parent.path_join(".notlight_boards_previous_%s" % token)
	var copied: Dictionary = _copy_board_storage_snapshot(source_root, staging)
	if not bool(copied.get("ok", false)):
		_delete_directory_recursive(staging)
		return copied
	var validation: Dictionary = _validate_board_storage_snapshot(staging)
	if not bool(validation.get("ok", false)):
		_delete_directory_recursive(staging)
		return {"ok": false, "error": NotLightL10n.text("settings.storage.existing_invalid") % str(validation.get("error", ""))}
	var had_destination: bool = DirAccess.dir_exists_absolute(destination)
	if had_destination and DirAccess.rename_absolute(destination, backup) != OK:
		_delete_directory_recursive(staging)
		return {"ok": false, "error": NotLightL10n.text("settings.storage.prepare_boards_failed")}
	if DirAccess.rename_absolute(staging, destination) != OK:
		if had_destination:
			DirAccess.rename_absolute(backup, destination)
		_delete_directory_recursive(staging)
		return {"ok": false, "error": NotLightL10n.text("settings.storage.prepare_boards_failed")}
	var committed: Dictionary = _validate_board_storage_snapshot(destination)
	if not bool(committed.get("ok", false)):
		_delete_directory_recursive(destination)
		if had_destination:
			DirAccess.rename_absolute(backup, destination)
		return {"ok": false, "error": NotLightL10n.text("settings.storage.existing_invalid") % str(committed.get("error", ""))}
	if had_destination:
		_delete_directory_recursive(backup)
	_prepared_external_fingerprint = _board_storage_fingerprint(destination)
	return {
		"ok": true,
		"root": destination,
		"changed": true,
		"copied_files": int(copied.get("files", 0)),
		"proof": _prepared_external_fingerprint,
	}


func cleanup_migrated_external_board_source() -> Dictionary:
	# Compatibility wrapper used by the direct storage smoke test. The durable app
	# path uses cleanup_migrated_board_source(), which can also resume after restart.
	if _prepared_external_root.is_empty() or _prepared_external_adopt_existing:
		return {"ok": true, "removed": false}
	var source_root: String = _absolute_path(_root_dir).simplify_path()
	var destination: String = _prepared_external_root.simplify_path()
	var cleaned: bool = cleanup_migrated_board_source(
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


func cleanup_migrated_board_source(source_root: String, destination_root: String, expected_proof: String = "") -> bool:
	# This function is deliberately independent of the in-memory prepared state so
	# a cleanup marker persisted in settings.json can be retried after a restart.
	var source: String = _absolute_path(source_root).simplify_path()
	var destination: String = _absolute_path(destination_root).simplify_path()
	if source.is_empty() or destination.is_empty():
		return false
	if _storage_path_key(source) == _storage_path_key(destination):
		return true
	if _path_is_inside(destination, source) or _path_is_inside(source, destination):
		return false
	var validation: Dictionary = _validate_board_storage_snapshot(destination)
	if not bool(validation.get("ok", false)):
		return false
	var proof: String = expected_proof.strip_edges().to_lower()
	if not proof.is_empty():
		if proof.length() != 64 or _board_storage_fingerprint(destination) != proof:
			return false
	elif _board_storage_fingerprint(source) != _board_storage_fingerprint(destination):
		return false

	# A board root can be the historical user://notlight directory, which also
	# contains settings/library/modules. Remove only BoardRepository-owned data.
	# This is also safe for an explicitly adopted existing root with extra siblings.
	var source_boards: String = source.path_join("boards")
	if DirAccess.dir_exists_absolute(source_boards) and not _delete_directory_recursive(source_boards):
		return false
	for index_name: String in ["index.json", "index.json.bak", "index.json.tmp"]:
		var source_index: String = source.path_join(index_name)
		if FileAccess.file_exists(source_index) and DirAccess.remove_absolute(source_index) != OK:
			return false
	if DirAccess.dir_exists_absolute(source) and _directory_is_empty_absolute(source):
		DirAccess.remove_absolute(source)
	return (
		not DirAccess.dir_exists_absolute(source_boards)
		and not FileAccess.file_exists(source.path_join("index.json"))
		and not FileAccess.file_exists(source.path_join("index.json.bak"))
		and not FileAccess.file_exists(source.path_join("index.json.tmp"))
	)


func mark_prepared_external_boards_activated() -> void:
	_clear_prepared_external_boards()


func _clear_prepared_external_boards() -> void:
	_prepared_external_root = ""
	_prepared_external_fingerprint = ""
	_prepared_external_adopt_existing = false


func _resolve_external_board_destination(selected_abs: String, source_root: String) -> String:
	if _storage_path_key(selected_abs) == _storage_path_key(source_root):
		return selected_abs
	if selected_abs.get_file().nocasecmp_to("boards") == 0:
		var parent: String = selected_abs.get_base_dir()
		if _looks_like_board_storage_root(parent):
			return parent
	if selected_abs.get_file().nocasecmp_to("NotLightBoards") == 0 or _looks_like_board_storage_root(selected_abs):
		return selected_abs
	for relative: String in ["notlight", "NotLightBoards"]:
		var candidate: String = selected_abs.path_join(relative).simplify_path()
		if DirAccess.dir_exists_absolute(candidate) and _looks_like_board_storage_root(candidate):
			return candidate
	return selected_abs.path_join("NotLightBoards").simplify_path()


func _looks_like_board_storage_root(root: String) -> bool:
	return DirAccess.dir_exists_absolute(root.path_join("boards")) or FileAccess.file_exists(root.path_join("index.json"))


func _board_storage_has_content(root: String) -> bool:
	var boards_path: String = root.path_join("boards")
	if not DirAccess.dir_exists_absolute(boards_path):
		return false
	for entry: String in DirAccess.get_directories_at(boards_path):
		if not _safe_id(entry).is_empty():
			return true
	return false


func _copy_board_storage_snapshot(source_root: String, destination_root: String) -> Dictionary:
	if DirAccess.dir_exists_absolute(destination_root):
		_delete_directory_recursive(destination_root)
	if DirAccess.make_dir_recursive_absolute(destination_root) != OK:
		return {"ok": false, "error": NotLightL10n.text("settings.storage.prepare_boards_failed")}
	var files_copied: int = 0
	var bytes_copied: int = 0
	var source_boards: String = source_root.path_join("boards")
	var destination_boards: String = destination_root.path_join("boards")
	if DirAccess.dir_exists_absolute(source_boards):
		var tree_result: Dictionary = _copy_directory_tree_verified_absolute(source_boards, destination_boards, 0)
		if not bool(tree_result.get("ok", false)):
			return tree_result
		files_copied += int(tree_result.get("files", 0))
		bytes_copied += int(tree_result.get("bytes", 0))
	else:
		DirAccess.make_dir_recursive_absolute(destination_boards)
	for index_name: String in ["index.json", "index.json.bak"]:
		var source_index: String = source_root.path_join(index_name)
		if FileAccess.file_exists(source_index):
			var target_index: String = destination_root.path_join(index_name)
			if DirAccess.copy_absolute(source_index, target_index) != OK:
				return {"ok": false, "error": NotLightL10n.text("settings.storage.prepare_boards_failed")}
			if FileAccess.get_sha256(source_index).to_lower() != FileAccess.get_sha256(target_index).to_lower():
				return {"ok": false, "error": NotLightL10n.text("settings.storage.verify_failed") % index_name}
			files_copied += 1
			bytes_copied += _file_size_absolute(source_index)
	return {"ok": true, "files": files_copied, "bytes": bytes_copied}


func _validate_board_storage_snapshot(root: String) -> Dictionary:
	var boards_path: String = root.path_join("boards")
	if not DirAccess.dir_exists_absolute(boards_path):
		return {"ok": false, "error": NotLightL10n.text("settings.storage.boards_folder_missing")}
	for entry: String in DirAccess.get_directories_at(boards_path):
		var safe_id: String = _safe_id(entry)
		if safe_id.is_empty():
			continue
		var board_dir: String = boards_path.path_join(safe_id)
		var manifest: Dictionary = _read_json_absolute(board_dir.path_join(MANIFEST_FILE))
		var document: Dictionary = _read_json_absolute(board_dir.path_join(BOARD_FILE))
		if manifest.is_empty() or document.is_empty() or not BoardDocumentSchema.is_supported(document):
			return {"ok": false, "error": NotLightL10n.text("settings.storage.board_invalid") % safe_id}
		var storage: Dictionary = document.get("storage", {}) as Dictionary
		var stroke_payload: String = str(storage.get("stroke_payload", "")).strip_edges()
		if not stroke_payload.is_empty() and not FileAccess.file_exists(board_dir.path_join(stroke_payload)):
			return {"ok": false, "error": NotLightL10n.text("settings.storage.board_invalid") % safe_id}
	return {"ok": true}


func _read_json_absolute(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return (parsed as Dictionary) if parsed is Dictionary else {}


func _board_storage_fingerprint(root: String) -> String:
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	for name: String in ["index.json", "index.json.bak"]:
		var path: String = root.path_join(name)
		var digest: String = FileAccess.get_sha256(path).to_lower() if FileAccess.file_exists(path) else "-"
		if context.update(("f|%s|%s\n" % [name, digest]).to_utf8_buffer()) != OK:
			return ""
	var boards_digest: String = _directory_tree_fingerprint_absolute(root.path_join("boards"), 0)
	if boards_digest.is_empty():
		boards_digest = "-"
	if context.update(("d|boards|%s\n" % boards_digest).to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()


func _directory_tree_fingerprint_absolute(root: String, depth: int) -> String:
	if depth > 64:
		return ""
	var directory: DirAccess = DirAccess.open(root)
	if directory == null:
		return ""
	var entries: PackedStringArray = PackedStringArray()
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
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
		var digest: String = _directory_tree_fingerprint_absolute(child_path, depth + 1) if is_directory else FileAccess.get_sha256(child_path).to_lower()
		if digest.length() != 64:
			return ""
		if context.update(("%s|%s|%s\n" % ["d" if is_directory else "f", child_name, digest]).to_utf8_buffer()) != OK:
			return ""
	return context.finish().hex_encode()


func _copy_directory_tree_verified_absolute(source: String, destination: String, depth: int) -> Dictionary:
	if depth > 64:
		return {"ok": false, "error": NotLightL10n.text("settings.storage.prepare_boards_failed")}
	var directory: DirAccess = DirAccess.open(source)
	if directory == null:
		return {"ok": false, "error": NotLightL10n.text("settings.storage.prepare_boards_failed")}
	if DirAccess.make_dir_recursive_absolute(destination) != OK:
		return {"ok": false, "error": NotLightL10n.text("settings.storage.prepare_boards_failed")}
	var files_copied: int = 0
	var bytes_copied: int = 0
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			if directory.is_link(entry):
				directory.list_dir_end()
				return {"ok": false, "error": NotLightL10n.text("settings.storage.prepare_boards_failed")}
			var src: String = source.path_join(entry)
			var dst: String = destination.path_join(entry)
			if directory.current_is_dir():
				var nested: Dictionary = _copy_directory_tree_verified_absolute(src, dst, depth + 1)
				if not bool(nested.get("ok", false)):
					directory.list_dir_end()
					return nested
				files_copied += int(nested.get("files", 0))
				bytes_copied += int(nested.get("bytes", 0))
			else:
				if DirAccess.copy_absolute(src, dst) != OK:
					directory.list_dir_end()
					return {"ok": false, "error": NotLightL10n.text("settings.storage.prepare_boards_failed")}
				if FileAccess.get_sha256(src).to_lower() != FileAccess.get_sha256(dst).to_lower():
					directory.list_dir_end()
					return {"ok": false, "error": NotLightL10n.text("settings.storage.verify_failed") % entry}
				files_copied += 1
				bytes_copied += _file_size_absolute(src)
		entry = directory.get_next()
	directory.list_dir_end()
	return {"ok": true, "files": files_copied, "bytes": bytes_copied}


func _file_size_absolute(path: String) -> int:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var length: int = file.get_length()
	file.close()
	return length


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


func _probe_writable_directory(path: String) -> String:
	var probe_path: String = path.path_join(".notlight_board_write_probe_%08x.tmp" % _rng.randi())
	var probe: FileAccess = FileAccess.open(probe_path, FileAccess.WRITE)
	if probe == null:
		return NotLightL10n.text("settings.storage.not_writable") % path
	var payload: PackedByteArray = "NotLight board storage write probe".to_utf8_buffer()
	var stored: bool = probe.store_buffer(payload)
	probe.flush()
	var write_error: Error = probe.get_error()
	probe.close()
	if not stored or write_error != OK:
		DirAccess.remove_absolute(probe_path)
		return NotLightL10n.text("settings.storage.not_writable") % path
	var readback: PackedByteArray = FileAccess.get_file_as_bytes(probe_path)
	DirAccess.remove_absolute(probe_path)
	return "" if readback == payload else NotLightL10n.text("settings.storage.not_writable") % path


func _path_is_inside(candidate: String, parent: String) -> bool:
	var clean_candidate: String = _storage_path_key(candidate)
	var clean_parent: String = _storage_path_key(parent)
	if clean_candidate.is_empty() or clean_parent.is_empty():
		return false
	return clean_candidate == clean_parent or clean_candidate.begins_with(clean_parent + "/")


func _storage_path_key(path: String) -> String:
	var clean: String = path.simplify_path().replace("\\", "/").trim_suffix("/")
	return clean.to_lower() if OS.get_name() == "Windows" else clean


func _absolute_path(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("user://") or path.begins_with("res://") else path


func _make_metadata(
	board_id: String,
	board_name: String,
	created_at: int,
	updated_at: int,
	transaction_id: String,
	asset_refs: PackedStringArray,
	module_refs: PackedStringArray
) -> Dictionary:
	var refs: Array[String] = []
	for asset_id: String in asset_refs:
		var clean_id: String = asset_id.strip_edges()
		if not clean_id.is_empty() and not refs.has(clean_id):
			refs.append(clean_id)
	refs.sort()
	var modules: Array[String] = []
	for module_id: String in module_refs:
		var clean_module_id: String = module_id.strip_edges().to_lower()
		if ModuleManifest.is_valid_module_id(clean_module_id) and not modules.has(clean_module_id):
			modules.append(clean_module_id)
	modules.sort()
	return {
		"schema": "notlight.board_manifest",
		"schema_version": MANIFEST_SCHEMA_VERSION,
		"id": board_id,
		"name": board_name,
		"created_at_unix": created_at,
		"updated_at_unix": updated_at,
		"storage_version": 5,
		"transaction_id": transaction_id,
		"relative_path": "boards/%s" % board_id,
		"asset_refs": refs,
		"module_refs": modules,
	}


func _normalize_metadata(source: Dictionary, board_id: String) -> Dictionary:
	var now: int = int(Time.get_unix_time_from_system())
	var refs: PackedStringArray = PackedStringArray()
	var raw_refs: Array = source.get("asset_refs", []) as Array
	for raw_ref: Variant in raw_refs:
		var asset_id: String = str(raw_ref).strip_edges()
		if not asset_id.is_empty() and not refs.has(asset_id):
			refs.append(asset_id)
	var module_refs: PackedStringArray = PackedStringArray()
	var raw_modules: Array = source.get("module_refs", []) as Array
	for raw_module: Variant in raw_modules:
		var module_id: String = str(raw_module).strip_edges().to_lower()
		if ModuleManifest.is_valid_module_id(module_id) and not module_refs.has(module_id):
			module_refs.append(module_id)
	return _make_metadata(
		board_id,
		str(source.get("name", NotLightL10n.text("hub.new_board"))),
		int(source.get("created_at_unix", now)),
		int(source.get("updated_at_unix", now)),
		str(source.get("transaction_id", "")),
		refs,
		module_refs
	)


func _read_best_manifest(board_id: String) -> Dictionary:
	var primary: Dictionary = _read_json(_manifest_path(board_id), false)
	if not primary.is_empty():
		return primary
	var backup: Dictionary = _read_json("%s.bak" % _manifest_path(board_id), false)
	return backup


func _read_consistent_board_pair(board_id: String) -> Dictionary:
	var manifest_path: String = _manifest_path(board_id)
	var document_path: String = _board_path(board_id)
	var primary_manifest: Dictionary = _read_json(manifest_path, false)
	var primary_document: Dictionary = _read_json(document_path, false)
	if _pair_is_consistent(primary_manifest, primary_document):
		return {"manifest": primary_manifest, "document": primary_document}
	var backup_manifest: Dictionary = _read_json("%s.bak" % manifest_path, false)
	var backup_document: Dictionary = _read_json("%s.bak" % document_path, false)
	if _pair_is_consistent(backup_manifest, backup_document):
		return {"manifest": backup_manifest, "document": backup_document}

	# Recovery path for packages written by older prototypes or interrupted
	# between the two atomic renames. Never delete such a board merely because
	# transaction IDs differ: if both JSON documents are valid and the board
	# schema is supported, opening it is safe and the next save will write a new
	# fully consistent transaction pair.
	var manifests: Array[Dictionary] = []
	if not primary_manifest.is_empty():
		manifests.append(primary_manifest)
	if not backup_manifest.is_empty():
		manifests.append(backup_manifest)
	var documents: Array[Dictionary] = []
	if not primary_document.is_empty() and BoardDocumentSchema.is_supported(primary_document):
		documents.append(primary_document)
	if not backup_document.is_empty() and BoardDocumentSchema.is_supported(backup_document):
		documents.append(backup_document)
	if manifests.is_empty() or documents.is_empty():
		return {}
	return {"manifest": manifests[0], "document": documents[0], "recovered": true}


func _pair_is_consistent(manifest: Dictionary, document: Dictionary) -> bool:
	if manifest.is_empty() or document.is_empty():
		return false
	var manifest_transaction: String = str(manifest.get("transaction_id", ""))
	var storage: Dictionary = document.get("storage", {}) as Dictionary
	var document_transaction: String = str(storage.get("transaction_id", ""))
	if manifest_transaction.is_empty() and document_transaction.is_empty():
		return true
	return not manifest_transaction.is_empty() and manifest_transaction == document_transaction


func _upsert_index_metadata(metadata: Dictionary) -> bool:
	var board_id: String = _safe_id(str(metadata.get("id", "")))
	if board_id.is_empty():
		_fail(NotLightL10n.text("runtime.data.board_repository.402841fd40"))
		return false
	var index: Dictionary = _read_supported_index()
	if index.is_empty():
		return _rebuild_index_from_manifests()
	var boards: Array[Dictionary] = []
	var replaced: bool = false
	var raw_boards: Array = index.get("boards", []) as Array
	for raw_board: Variant in raw_boards:
		if raw_board is not Dictionary:
			continue
		var record: Dictionary = raw_board as Dictionary
		var record_id: String = _safe_id(str(record.get("id", "")))
		if record_id.is_empty():
			continue
		if record_id == board_id:
			boards.append(metadata.duplicate(true))
			replaced = true
		else:
			boards.append(_normalize_metadata(record, record_id))
	if not replaced:
		boards.append(metadata.duplicate(true))
	return _write_index_records(boards)


func _remove_index_metadata(board_id: String) -> bool:
	var index: Dictionary = _read_supported_index()
	if index.is_empty():
		return _rebuild_index_from_manifests()
	var boards: Array[Dictionary] = []
	var raw_boards: Array = index.get("boards", []) as Array
	for raw_board: Variant in raw_boards:
		if raw_board is not Dictionary:
			continue
		var record: Dictionary = raw_board as Dictionary
		var record_id: String = _safe_id(str(record.get("id", "")))
		if record_id.is_empty() or record_id == board_id:
			continue
		boards.append(_normalize_metadata(record, record_id))
	return _write_index_records(boards)


func _read_supported_index() -> Dictionary:
	var primary: Dictionary = _read_json(_index_path, false)
	if _index_is_supported(primary):
		return primary
	var backup: Dictionary = _read_json("%s.bak" % _index_path, false)
	if _index_is_supported(backup):
		return backup
	return {}


func _index_is_supported(index: Dictionary) -> bool:
	return (
		str(index.get("schema", "")) == "notlight.board_index"
		and int(index.get("schema_version", 0)) == INDEX_SCHEMA_VERSION
		and index.get("boards", []) is Array
	)


func _write_index_records(boards: Array[Dictionary]) -> bool:
	boards.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("updated_at_unix", 0)) > int(right.get("updated_at_unix", 0))
	)
	var index: Dictionary = {
		"schema": "notlight.board_index",
		"schema_version": INDEX_SCHEMA_VERSION,
		"boards": boards,
	}
	return _write_json_atomic(_index_path, index)


func _rebuild_index_from_manifests() -> bool:
	if not _ensure_directory(_boards_dir):
		return false
	var previous_index: Dictionary = _read_supported_index()
	var previous_by_id: Dictionary = {}
	if not previous_index.is_empty():
		var previous_records: Array = previous_index.get("boards", []) as Array
		for raw_record: Variant in previous_records:
			if raw_record is not Dictionary:
				continue
			var record: Dictionary = raw_record as Dictionary
			var record_id: String = _safe_id(str(record.get("id", "")))
			if not record_id.is_empty():
				previous_by_id[record_id] = record.duplicate(true)

	var boards: Array[Dictionary] = []
	var discovered: Dictionary = {}
	var directories: PackedStringArray = DirAccess.get_directories_at(_boards_dir)
	for entry: String in directories:
		var board_id: String = _safe_id(entry)
		if board_id.is_empty():
			continue
		# Hub discovery is intentionally manifest-first. A transiently damaged or
		# older board document may fail to open, but that must not make the board
		# vanish from the Hub. Opening still performs the stricter pair validation.
		var manifest: Dictionary = _read_best_manifest(board_id)
		if manifest.is_empty():
			continue
		boards.append(_normalize_metadata(manifest, board_id))
		discovered[board_id] = true

	# An index entry is cheap metadata and is safer to preserve than to silently
	# erase when a package is temporarily unreadable (antivirus/file sync/power
	# loss). It remains visible in Hub and opening it will surface a real error
	# instead of making the user's board appear deleted.
	for raw_id: Variant in previous_by_id.keys():
		var board_id: String = str(raw_id)
		if discovered.has(board_id):
			continue
		var board_dir: String = _board_dir(board_id)
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(board_dir)):
			continue
		var previous_record: Dictionary = previous_by_id[board_id] as Dictionary
		boards.append(_normalize_metadata(previous_record, board_id))
	return _write_index_records(boards)


func _ensure_board_directories(board_dir: String) -> bool:
	# Stage 4 moves original media into the global content-addressed Asset Library.
	# Board packages now contain only board state and lightweight references.
	return _ensure_directory(board_dir)


func _ensure_directory(path: String) -> bool:
	var absolute: String = ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(absolute):
		return true
	var error: Error = DirAccess.make_dir_recursive_absolute(absolute)
	if error != OK:
		_fail(NotLightL10n.text("runtime.data.board_repository.1a58656222") % path)
		return false
	return true


func _write_board_package_atomic(board_id: String, metadata: Dictionary, document: Dictionary, stroke_payload: PackedByteArray) -> bool:
	var storage: Dictionary = document.get("storage", {}) as Dictionary
	var payload_filename: String = str(storage.get("stroke_payload", "")).strip_edges()
	if not payload_filename.is_empty():
		if stroke_payload.is_empty() or not _write_binary_atomic(_board_dir(board_id).path_join(payload_filename), stroke_payload):
			return false
	var document_path: String = _board_path(board_id)
	var manifest_path: String = _manifest_path(board_id)
	var document_temp: String = "%s.tmp" % document_path
	var manifest_temp: String = "%s.tmp" % manifest_path
	if not _write_json_file(document_temp, document):
		return false
	if not _write_json_file(manifest_temp, metadata):
		_remove_file_if_exists(document_temp)
		return false
	var document_backup: String = "%s.bak" % document_path
	var manifest_backup: String = "%s.bak" % manifest_path
	_remove_file_if_exists(document_backup)
	_remove_file_if_exists(manifest_backup)
	var had_document: bool = FileAccess.file_exists(document_path)
	var had_manifest: bool = FileAccess.file_exists(manifest_path)
	if had_document and not _rename_file(document_path, document_backup):
		_cleanup_temporary_pair(document_temp, manifest_temp)
		return false
	if had_manifest and not _rename_file(manifest_path, manifest_backup):
		if had_document:
			_rename_file(document_backup, document_path)
		_cleanup_temporary_pair(document_temp, manifest_temp)
		return false
	if not _rename_file(document_temp, document_path):
		_restore_pair(document_path, manifest_path, document_backup, manifest_backup, had_document, had_manifest)
		_remove_file_if_exists(manifest_temp)
		return false
	if not _rename_file(manifest_temp, manifest_path):
		_remove_file_if_exists(document_path)
		_remove_file_if_exists(manifest_temp)
		_restore_pair(document_path, manifest_path, document_backup, manifest_backup, had_document, had_manifest)
		return false
	return true


func _restore_pair(
	document_path: String,
	manifest_path: String,
	document_backup: String,
	manifest_backup: String,
	had_document: bool,
	had_manifest: bool
) -> void:
	if had_document and FileAccess.file_exists(document_backup):
		_rename_file(document_backup, document_path)
	if had_manifest and FileAccess.file_exists(manifest_backup):
		_rename_file(manifest_backup, manifest_path)


func _cleanup_temporary_pair(document_temp: String, manifest_temp: String) -> void:
	_remove_file_if_exists(document_temp)
	_remove_file_if_exists(manifest_temp)


func _write_json_atomic(path: String, data: Dictionary) -> bool:
	var temporary_path: String = "%s.tmp" % path
	var backup_path: String = "%s.bak" % path
	if not _write_json_file(temporary_path, data):
		return false
	_remove_file_if_exists(backup_path)
	var had_original: bool = FileAccess.file_exists(path)
	if had_original and not _rename_file(path, backup_path):
		_remove_file_if_exists(temporary_path)
		return false
	if not _rename_file(temporary_path, path):
		if had_original and FileAccess.file_exists(backup_path):
			_rename_file(backup_path, path)
		return false
	return true


func _write_json_file(path: String, data: Dictionary) -> bool:
	if not _ensure_directory(path.get_base_dir()):
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail(NotLightL10n.text("runtime.data.board_repository.43208592f9") % path)
		return false
	var write_ok: bool = file.store_string(JSON.stringify(data, "  ", false, true))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if not write_ok or write_error != OK:
		_fail(NotLightL10n.text("runtime.data.board_repository.41a1d2d457") % path)
		return false
	return true


func _rename_file(from_path: String, to_path: String) -> bool:
	var error: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(from_path),
		ProjectSettings.globalize_path(to_path)
	)
	if error != OK:
		_fail(NotLightL10n.text("runtime.data.board_repository.9aeb41f8f3") % from_path)
		return false
	return true


func _remove_file_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _read_json(path: String, report_error: bool = true) -> Dictionary:
	if not FileAccess.file_exists(path):
		if report_error:
			_fail(NotLightL10n.text("runtime.data.board_repository.e3f1de359a") % path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		if report_error:
			_fail(NotLightL10n.text("runtime.data.board_repository.19fbe3d84f") % path)
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		if report_error:
			_fail(NotLightL10n.text("runtime.data.board_repository.54e8c2db8a") % path)
		return {}
	return (parsed as Dictionary).duplicate(true)



func _write_binary_atomic(path: String, bytes: PackedByteArray) -> bool:
	var temporary_path: String = "%s.tmp" % path
	if not _ensure_directory(path.get_base_dir()):
		return false
	var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		_fail(NotLightL10n.text("runtime.data.board_repository.c96b05fb6b") % path)
		return false
	var write_ok: bool = file.store_buffer(bytes)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if not write_ok or write_error != OK:
		_remove_file_if_exists(temporary_path)
		_fail(NotLightL10n.text("runtime.data.board_repository.ebc1d9c079") % path)
		return false
	if FileAccess.file_exists(path):
		_remove_file_if_exists(path)
	if not _rename_file(temporary_path, path):
		_remove_file_if_exists(temporary_path)
		return false
	return true


func _read_stroke_payload(board_id: String, document: Dictionary) -> PackedByteArray:
	var storage: Dictionary = document.get("storage", {}) as Dictionary
	var filename: String = str(storage.get("stroke_payload", "")).strip_edges()
	if filename.is_empty() or filename.get_file() != filename or not filename.begins_with(STROKE_PAYLOAD_PREFIX) or not filename.ends_with(".bin"):
		return PackedByteArray()
	var path: String = _board_dir(board_id).path_join(filename)
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var byte_count: int = int(file.get_length())
	var bytes: PackedByteArray = file.get_buffer(byte_count)
	file.close()
	return bytes


func _cleanup_stale_stroke_payloads(board_id: String, current_document: Dictionary) -> void:
	var keep: Dictionary = {}
	var current_storage: Dictionary = current_document.get("storage", {}) as Dictionary
	var current_name: String = str(current_storage.get("stroke_payload", "")).strip_edges()
	if not current_name.is_empty():
		keep[current_name] = true
	var backup_document: Dictionary = _read_json("%s.bak" % _board_path(board_id), false)
	if not backup_document.is_empty():
		var backup_storage: Dictionary = backup_document.get("storage", {}) as Dictionary
		var backup_name: String = str(backup_storage.get("stroke_payload", "")).strip_edges()
		if not backup_name.is_empty():
			keep[backup_name] = true
	var entries: PackedStringArray = DirAccess.get_files_at(_board_dir(board_id))
	for filename: String in entries:
		if filename.begins_with(STROKE_PAYLOAD_PREFIX) and filename.ends_with(".bin") and not keep.has(filename):
			_remove_file_if_exists(_board_dir(board_id).path_join(filename))

func _delete_directory_recursive(path: String) -> bool:
	var absolute: String = ProjectSettings.globalize_path(path) if path.begins_with("user://") or path.begins_with("res://") else path
	if not DirAccess.dir_exists_absolute(absolute):
		return true
	var parent: DirAccess = DirAccess.open(absolute.get_base_dir())
	var entry_name: String = absolute.get_file()
	if parent != null and not entry_name.is_empty() and parent.is_link(entry_name):
		var link_error: Error = DirAccess.remove_absolute(absolute)
		if link_error != OK:
			_fail(NotLightL10n.text("runtime.data.board_repository.a686b8b2a0") % path)
			return false
		return true
	var directory: DirAccess = DirAccess.open(absolute)
	if directory == null:
		_fail(NotLightL10n.text("runtime.data.board_repository.4b39163cc4") % path)
		return false
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child: String = absolute.path_join(entry)
			if directory.is_link(entry):
				if DirAccess.remove_absolute(child) != OK:
					directory.list_dir_end()
					_fail(NotLightL10n.text("runtime.data.board_repository.a686b8b2a0") % child)
					return false
			elif directory.current_is_dir():
				if not _delete_directory_recursive(child):
					directory.list_dir_end()
					return false
			else:
				var remove_error: Error = DirAccess.remove_absolute(child)
				if remove_error != OK:
					directory.list_dir_end()
					_fail(NotLightL10n.text("runtime.data.board_repository.dc35e3f1e2") % child)
					return false
		entry = directory.get_next()
	directory.list_dir_end()
	var error: Error = DirAccess.remove_absolute(absolute)
	if error != OK:
		_fail(NotLightL10n.text("runtime.data.board_repository.425d3430cc") % path)
		return false
	return true


func _make_board_id() -> String:
	var unix_time: int = int(Time.get_unix_time_from_system())
	return "board_%s_%08x%08x" % [unix_time, _rng.randi(), _rng.randi()]


func _make_transaction_id() -> String:
	return "%s_%08x%08x" % [Time.get_ticks_usec(), _rng.randi(), _rng.randi()]


func _safe_id(value: String) -> String:
	var clean: String = value.strip_edges()
	if clean.is_empty():
		return ""
	const ALLOWED: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
	for index: int in range(clean.length()):
		if ALLOWED.find(clean.substr(index, 1)) == -1:
			return ""
	return clean


func _board_dir(board_id: String) -> String:
	return _boards_dir.path_join(board_id)


func _manifest_path(board_id: String) -> String:
	return _board_dir(board_id).path_join(MANIFEST_FILE)


func _board_path(board_id: String) -> String:
	return _board_dir(board_id).path_join(BOARD_FILE)


func _clear_error() -> void:
	_last_error = ""


func _fail(message: String) -> void:
	_last_error = message
	push_error(message)
	repository_error.emit(message)
