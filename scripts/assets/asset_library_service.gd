# SPDX-License-Identifier: GPL-3.0-or-later
class_name AssetLibraryService
extends Node

signal library_changed
signal asset_metadata_changed(asset_id: String)
signal folders_changed
signal references_changed
signal import_progress(job_id: String, source_path: String, progress: float)
signal import_finished(asset_id: String, duplicate: bool)
signal import_job_finished(job_id: String, asset_id: String, duplicate: bool)
signal import_failed(message: String)
signal import_job_failed(job_id: String, source_path: String, message: String)
signal import_queue_changed(pending_count: int)
signal import_preflight_started(request_id: String, total_count: int)
signal import_preflight_progress(request_id: String, completed_count: int, total_count: int, source_path: String)
signal import_preflight_completed(request_id: String, results: Array)
signal import_preflight_cancelled(request_id: String)
signal import_preflight_failed(request_id: String, message: String)
signal library_error(message: String)

const ROOT_DIR: String = "user://notlight/library"
const CATALOG_FILE: String = "catalog.json"
const FOLDER_ANY: String = "*"
const USAGE_ALL: int = 0
const USAGE_USED: int = 1
const USAGE_UNUSED: int = 2

var catalog: AssetCatalog = AssetCatalog.new()
var blobs: AssetBlobStore = AssetBlobStore.new()
var references: AssetReferenceIndex = AssetReferenceIndex.new()
var importer: AssetImportPipeline
var preflight: AssetImportPreflightService
var repository: BoardRepository
var _last_error: String = ""
var _initialized: bool = false
var _root_dir: String = ROOT_DIR
var _prepared_external_root: String = ""
var _prepared_external_catalog_sha256: String = ""


func setup(board_repository: BoardRepository, library_root: String = ROOT_DIR) -> bool:
	repository = board_repository
	_initialized = false
	_root_dir = library_root.strip_edges()
	if _root_dir.is_empty():
		_root_dir = ROOT_DIR
	_clear_error()
	if not blobs.setup(_root_dir):
		_fail(blobs.get_last_error())
		return false
	if not catalog.setup(_root_dir.path_join(CATALOG_FILE)):
		_fail(catalog.get_last_error())
		return false
	importer = AssetImportPipeline.new()
	importer.name = "AssetImportPipeline"
	add_child(importer)
	importer.configure(catalog, blobs)
	importer.import_progress.connect(_on_import_progress)
	importer.import_completed.connect(_on_import_completed)
	importer.import_failed.connect(_on_import_failed)
	importer.queue_changed.connect(_on_import_queue_changed)
	preflight = AssetImportPreflightService.new()
	preflight.name = "AssetImportPreflightService"
	add_child(preflight)
	preflight.configure(catalog, blobs)
	preflight.preflight_started.connect(_on_preflight_started)
	preflight.preflight_progress.connect(_on_preflight_progress)
	preflight.preflight_completed.connect(_on_preflight_completed)
	preflight.preflight_cancelled.connect(_on_preflight_cancelled)
	preflight.preflight_failed.connect(_on_preflight_failed)
	if repository != null:
		if not repository.board_manifest_changed.is_connected(_on_board_manifest_changed):
			repository.board_manifest_changed.connect(_on_board_manifest_changed)
		if not repository.board_deleted.is_connected(_on_board_deleted):
			repository.board_deleted.connect(_on_board_deleted)
	refresh_references()
	_initialized = true
	return true


func is_available() -> bool:
	return _initialized


func get_last_error() -> String:
	return _last_error


func get_root_directory() -> String:
	return _root_dir


func make_catalog_snapshot() -> Dictionary:
	return catalog.make_snapshot() if _initialized else {}


func apply_catalog_import_batch(folder_records: Array[Dictionary], asset_records: Array[Dictionary]) -> bool:
	if not _require_ready():
		return false
	if not catalog.apply_import_batch(folder_records, asset_records):
		_fail(catalog.get_last_error())
		return false
	refresh_references()
	folders_changed.emit()
	library_changed.emit()
	return true


func restore_catalog_snapshot(snapshot: Dictionary) -> bool:
	if not _require_ready():
		return false
	if not catalog.restore_snapshot(snapshot):
		_fail(catalog.get_last_error())
		return false
	refresh_references()
	folders_changed.emit()
	library_changed.emit()
	return true


func repair_catalog_blob_location(asset_id: String, relative_path: String, byte_size: int, extension: String) -> bool:
	if not _require_ready():
		return false
	if not catalog.repair_blob_location(asset_id, relative_path, byte_size, extension):
		_fail(catalog.get_last_error())
		return false
	library_changed.emit()
	return true


func has_pending_imports() -> bool:
	return importer != null and importer.pending_count() > 0


func cancel_imports() -> void:
	if importer != null:
		importer.cancel_all()


func list_assets(
	query: String = "",
	kind_filter: int = AssetKinds.ANY,
	folder_id: String = FOLDER_ANY,
	usage_filter: int = USAGE_ALL,
	tag_filter: String = ""
) -> Array[Dictionary]:
	var page: Dictionary = query_assets(query, kind_filter, folder_id, usage_filter, 0, -1, tag_filter)
	var result: Array[Dictionary] = []
	var records: Array = page.get("records", []) as Array
	for raw_record: Variant in records:
		if raw_record is Dictionary:
			result.append((raw_record as Dictionary).duplicate(true))
	return result


func query_assets(
	query: String,
	kind_filter: int,
	folder_id: String,
	usage_filter: int,
	offset: int,
	limit: int,
	tag_filter: String = ""
) -> Dictionary:
	var records: Array[Dictionary] = []
	if not _initialized:
		return {"records": records, "total": 0}
	var search_tokens: PackedStringArray = _search_tokens(query)
	var required_tag: String = tag_filter.strip_edges().to_lower()
	var safe_offset: int = maxi(0, offset)
	var matched_count: int = 0
	for asset: Dictionary in catalog.list_assets_readonly():
		var asset_id: String = str(asset.get("id", ""))
		if kind_filter != AssetKinds.ANY and int(asset.get("kind", AssetKinds.OTHER)) != kind_filter:
			continue
		if folder_id != FOLDER_ANY and str(asset.get("folder_id", "")) != folder_id:
			continue
		var used: bool = references.is_used(asset_id)
		if usage_filter == USAGE_USED and not used:
			continue
		if usage_filter == USAGE_UNUSED and used:
			continue
		var tags: PackedStringArray = _asset_tags(asset)
		if not required_tag.is_empty() and not _contains_tag(tags, required_tag):
			continue
		if not search_tokens.is_empty() and not _asset_matches_tokens(asset, tags, search_tokens):
			continue
		if matched_count >= safe_offset and (limit < 0 or records.size() < limit):
			var enriched: Dictionary = asset.duplicate(true)
			enriched["usage_count"] = references.usage_count(asset_id)
			enriched["board_usage_count"] = references.board_usage_count(asset_id)
			enriched["note_embed_usage_count"] = references.note_embed_usage_count(asset_id)
			enriched["feature_usage_count"] = references.external_usage_count(asset_id)
			enriched["used_by_features"] = references.external_labels_for(asset_id)
			enriched["used"] = used
			records.append(enriched)
		matched_count += 1
	return {"records": records, "total": matched_count}


func list_tags() -> Array[Dictionary]:
	var counts: Dictionary = {}
	var labels: Dictionary = {}
	if not _initialized:
		return []
	for asset: Dictionary in catalog.list_assets_readonly():
		for tag: String in _asset_tags(asset):
			var normalized: String = tag.to_lower()
			counts[normalized] = int(counts.get(normalized, 0)) + 1
			if not labels.has(normalized):
				labels[normalized] = tag
	var result: Array[Dictionary] = []
	for raw_key: Variant in counts.keys():
		var key: String = str(raw_key)
		result.append({"tag": str(labels.get(key, key)), "normalized": key, "count": int(counts[key])})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("tag", "")).naturalnocasecmp_to(str(right.get("tag", ""))) < 0
	)
	return result


func update_asset_details(asset_id: String, description: String, tags: PackedStringArray) -> bool:
	if not _require_ready():
		return false
	if not catalog.update_asset(asset_id, {"description": description, "tags": tags}):
		_fail(catalog.get_last_error())
		return false
	# Description/tags are catalog metadata. Do not invalidate every media/cache/
	# Notes consumer through the coarse library_changed signal on each autosave.
	# Metadata-aware UI can refresh exactly the surfaces that depend on search/tags.
	asset_metadata_changed.emit(asset_id)
	return true


func _search_tokens(query: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for raw_part: String in query.strip_edges().to_lower().split(" ", false):
		var token: String = raw_part.strip_edges()
		if not token.is_empty():
			result.append(token)
	return result


func _asset_tags(asset: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var raw_tags: Variant = asset.get("tags", [])
	if raw_tags is Array or raw_tags is PackedStringArray:
		for raw_tag: Variant in raw_tags:
			var tag: String = str(raw_tag).strip_edges()
			if not tag.is_empty():
				result.append(tag)
	return result


func _contains_tag(tags: PackedStringArray, normalized_tag: String) -> bool:
	for tag: String in tags:
		if tag.to_lower() == normalized_tag:
			return true
	return false


func _asset_matches_tokens(asset: Dictionary, tags: PackedStringArray, tokens: PackedStringArray) -> bool:
	var tag_text: String = " ".join(tags)
	var haystack: String = "%s %s %s %s %s %s" % [
		str(asset.get("display_name", "")),
		str(asset.get("original_filename", "")),
		str(asset.get("extension", "")),
		AssetKinds.label(int(asset.get("kind", AssetKinds.OTHER))),
		str(asset.get("description", "")),
		tag_text,
	]
	haystack = haystack.to_lower()
	for token: String in tokens:
		var needle: String = token
		if needle.begins_with("tag:"):
			needle = needle.trim_prefix("tag:").trim_prefix("#")
			if not _contains_tag(tags, needle):
				return false
		elif needle.begins_with("#"):
			if not _contains_tag(tags, needle.trim_prefix("#")):
				return false
		elif not haystack.contains(needle):
			return false
	return true


func list_folders() -> Array[Dictionary]:
	return catalog.list_folders() if _initialized else []


func get_folder(folder_id: String) -> Dictionary:
	return catalog.get_folder(folder_id) if _initialized else {}


func get_asset(asset_id: String) -> Dictionary:
	if not _initialized:
		return {}
	var record: Dictionary = catalog.get_asset(asset_id)
	if record.is_empty():
		return {}
	record["usage_count"] = references.usage_count(asset_id)
	record["board_usage_count"] = references.board_usage_count(asset_id)
	record["note_embed_usage_count"] = references.note_embed_usage_count(asset_id)
	record["feature_usage_count"] = references.external_usage_count(asset_id)
	record["used_by_features"] = references.external_labels_for(asset_id)
	record["used"] = references.is_used(asset_id)
	record["used_on_boards"] = references.board_names_for(asset_id)
	record["used_on_board_entries"] = references.board_entries_for(asset_id)
	record["embedded_in_notes"] = _note_embed_names_for(asset_id)
	record["embedded_in_note_entries"] = _note_embed_entries_for(asset_id)
	return record


func find_asset_by_hash(hash_sha256: String) -> Dictionary:
	if not _initialized:
		return {}
	var record: Dictionary = catalog.find_asset_by_hash(hash_sha256)
	if record.is_empty():
		return {}
	var asset_id: String = str(record.get("id", ""))
	record["usage_count"] = references.usage_count(asset_id)
	record["board_usage_count"] = references.board_usage_count(asset_id)
	record["note_embed_usage_count"] = references.note_embed_usage_count(asset_id)
	record["feature_usage_count"] = references.external_usage_count(asset_id)
	record["used_by_features"] = references.external_labels_for(asset_id)
	record["used"] = references.is_used(asset_id)
	record["used_on_boards"] = references.board_names_for(asset_id)
	record["used_on_board_entries"] = references.board_entries_for(asset_id)
	record["embedded_in_notes"] = _note_embed_names_for(asset_id)
	record["embedded_in_note_entries"] = _note_embed_entries_for(asset_id)
	return record


func _note_embed_names_for(asset_id: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for note_id: String in references.note_ids_for(asset_id):
		var note: Dictionary = catalog.get_asset(note_id)
		var label: String = str(note.get("display_name", note_id)).strip_edges() if not note.is_empty() else note_id
		if not label.is_empty():
			result.append(label)
	result.sort()
	return result


func _note_embed_entries_for(asset_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for note_id: String in references.note_ids_for(asset_id):
		var note: Dictionary = catalog.get_asset(note_id)
		var label: String = str(note.get("display_name", note_id)).strip_edges() if not note.is_empty() else note_id
		var folder_id: String = str(note.get("folder_id", "")).strip_edges() if not note.is_empty() else ""
		result.append({
			"id": note_id,
			"name": label if not label.is_empty() else note_id,
			"folder_path": folder_path(folder_id) if not folder_id.is_empty() else "",
		})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_name: String = str(left.get("name", ""))
		var right_name: String = str(right.get("name", ""))
		var compare: int = left_name.naturalnocasecmp_to(right_name)
		if compare != 0:
			return compare < 0
		return str(left.get("id", "")) < str(right.get("id", ""))
	)
	return result


func set_feature_asset_references(owner_id: String, asset_ids: PackedStringArray, label: String = "") -> void:
	if not _initialized:
		return
	if references.set_external_refs(owner_id, asset_ids, label):
		references_changed.emit()
		library_changed.emit()


func clear_feature_asset_references(owner_id: String) -> void:
	if not _initialized:
		return
	if references.remove_external_refs(owner_id):
		references_changed.emit()
		library_changed.emit()


func set_note_embed_hash_references(note_id: String, hashes: PackedStringArray) -> void:
	if not _initialized:
		return
	if references.set_note_embed_refs(note_id, _asset_ids_for_embed_hashes(hashes)):
		references_changed.emit()


func _asset_ids_for_embed_hashes(hashes: PackedStringArray) -> PackedStringArray:
	var asset_ids: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	for hash_sha256: String in hashes:
		var asset: Dictionary = catalog.find_asset_by_hash(hash_sha256)
		if asset.is_empty():
			continue
		var kind: int = int(asset.get("kind", AssetKinds.OTHER))
		var asset_id: String = str(asset.get("id", "")).strip_edges()
		if asset_id.is_empty() or not NoteResourceEmbed.is_embeddable_kind(kind) or seen.has(asset_id):
			continue
		seen[asset_id] = true
		asset_ids.append(asset_id)
	asset_ids.sort()
	return asset_ids


func clear_note_embed_references(note_id: String) -> void:
	if references.remove_note_embed_refs(note_id):
		references_changed.emit()


func resolve_asset_path(asset_id: String) -> String:
	if not _initialized:
		return ""
	var asset: Dictionary = catalog.get_asset(asset_id)
	if asset.is_empty():
		return ""
	return blobs.resolve_blob_path(str(asset.get("blob_relpath", "")))


func resolve_blob_relative(relative_path: String) -> String:
	if not _initialized:
		return ""
	return blobs.resolve_blob_path(relative_path)


func update_asset_metadata(asset_id: String, metadata: Dictionary) -> bool:
	if not _require_ready():
		return false
	if not catalog.update_asset(asset_id, {"metadata": metadata.duplicate(true)}):
		_fail(catalog.get_last_error())
		return false
	library_changed.emit()
	return true


func register_managed_asset(record: Dictionary) -> bool:
	# First-party core subsystems may stage and verify bytes themselves (Notes is
	# the first consumer) and then atomically register the logical Library record.
	# The catalog still owns schema validation and durable persistence.
	if not _require_ready():
		return false
	if not catalog.add_asset(record.duplicate(true)):
		_fail(catalog.get_last_error())
		return false
	library_changed.emit()
	return true


func replace_asset_primary_blob(
	asset_id: String,
	hash_sha256: String,
	relative_path: String,
	byte_size: int,
	extension: String,
	metadata: Dictionary
) -> bool:
	if not _require_ready():
		return false
	var current: Dictionary = catalog.get_asset(asset_id)
	var current_hash: String = str(current.get("hash_sha256", "")).strip_edges().to_lower()
	var next_hash: String = hash_sha256.strip_edges().to_lower()
	if current_hash != next_hash and references.note_ids_for(asset_id).is_empty():
		# Destructive canonical replacement is rare; pay a bounded durable Notes
		# scan only when the in-memory index currently says the blob is unpinned.
		# This closes the startup race before background Note indexing has finished.
		_synchronize_note_embed_references_for_cleanup()
	# Resource embeds are immutable SHA-256 pins. Replacing the canonical bytes of
	# a pinned Library resource would make existing note Markdown resolve to a
	# different/missing object. Keep the old primary durable until the user removes
	# those embeds; playback may still switch to derived media variants normally.
	if current_hash != next_hash and references.note_ids_for(asset_id).size() > 0:
		_fail(NotLightL10n.text("runtime.assets.asset_library_service.8860b36f0f"))
		return false
	if not catalog.replace_asset_blob(asset_id, hash_sha256, relative_path, byte_size, extension, metadata):
		_fail(catalog.get_last_error())
		return false
	library_changed.emit()
	return true


func prepare_external_library(parent_directory: String) -> Dictionary:
	# Stage-7 migration is intentionally conservative: copy into a dedicated
	# NotLightLibrary child, keep the current library untouched, and only switch
	# settings after a complete copy succeeds.
	if not _require_ready():
		return {"ok": false, "error": get_last_error()}
	var parent: String = parent_directory.strip_edges()
	if parent.is_empty():
		return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.1fcce131db")}
	if parent.begins_with("res://") or parent.begins_with("user://"):
		parent = ProjectSettings.globalize_path(parent)
	var parent_abs: String = parent.simplify_path()
	if not DirAccess.dir_exists_absolute(parent_abs):
		return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.1f700bbf3f")}
	var destination: String = parent_abs.path_join("NotLightLibrary")
	var destination_catalog: String = destination.path_join(CATALOG_FILE)
	var source_root: String = ProjectSettings.globalize_path(_root_dir).simplify_path()
	if _storage_path_key(destination) == _storage_path_key(source_root):
		_prepared_external_root = ""
		_prepared_external_catalog_sha256 = ""
		return {"ok": true, "root": destination, "existing": true, "same_location": true, "restart_required": false}
	if _path_is_inside(parent_abs, source_root):
		return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.93004ab9b8")}
	var writable_error: String = _probe_writable_directory(parent_abs)
	if not writable_error.is_empty():
		return {"ok": false, "error": writable_error}
	if DirAccess.dir_exists_absolute(destination):
		if not FileAccess.file_exists(destination_catalog):
			return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.5cae9fedcf")}
		var existing_validation: Dictionary = _validate_library_snapshot(destination)
		if not bool(existing_validation.get("ok", false)):
			return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.3b7d479ffc") % str(existing_validation.get("error", NotLightL10n.text("runtime.assets.asset_library_service.c248a6fec6")))}
		var source_catalog_path: String = source_root.path_join(CATALOG_FILE)
		if not _files_equal(source_catalog_path, destination_catalog):
			return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.f2daccc3ec")}
		var source_validation: Dictionary = _validate_library_snapshot(source_root)
		if not bool(source_validation.get("ok", false)):
			return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.ec46cb7ca9") % str(source_validation.get("error", NotLightL10n.text("runtime.assets.asset_library_service.c248a6fec6")))}
		_prepared_external_root = destination
		_prepared_external_catalog_sha256 = FileAccess.get_sha256(destination_catalog).to_lower()
		return {"ok": true, "root": destination, "existing": true, "restart_required": true}
	var staging: String = parent_abs.path_join(".notlight_library_staging")
	if DirAccess.dir_exists_absolute(staging):
		_delete_directory_absolute(staging)
	var make_error: Error = DirAccess.make_dir_recursive_absolute(staging)
	if make_error != OK:
		return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.89eef5b2de")}
	var copy_result: Dictionary = _copy_directory_tree(source_root, staging)
	if not bool(copy_result.get("ok", false)):
		_delete_directory_absolute(staging)
		return copy_result
	if not FileAccess.file_exists(staging.path_join(CATALOG_FILE)):
		_delete_directory_absolute(staging)
		return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.1035e55f84")}
	var snapshot_validation: Dictionary = _validate_library_snapshot(staging)
	if not bool(snapshot_validation.get("ok", false)):
		_delete_directory_absolute(staging)
		return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.2861d38d1a") % str(snapshot_validation.get("error", NotLightL10n.text("runtime.assets.asset_library_service.c248a6fec6")))}
	var rename_error: Error = DirAccess.rename_absolute(staging, destination)
	if rename_error != OK:
		_delete_directory_absolute(staging)
		return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.8701595bea")}
	_prepared_external_root = destination
	_prepared_external_catalog_sha256 = FileAccess.get_sha256(destination.path_join(CATALOG_FILE)).to_lower()
	return {
		"ok": true,
		"root": destination,
		"existing": false,
		"copied_files": int(copy_result.get("files", 0)),
		"copied_bytes": int(copy_result.get("bytes", 0)),
		"restart_required": true,
	}


func has_prepared_external_library() -> bool:
	return not _prepared_external_root.is_empty()


func get_prepared_external_library_root() -> String:
	return _prepared_external_root


func finalize_prepared_external_library() -> Dictionary:
	# The initial Settings copy is only a preparation snapshot. The active setting
	# is intentionally not changed until a clean application exit. Re-copying here,
	# after Notes/board state has been flushed, prevents edits made between choosing
	# a disk and closing NotLight from disappearing after the restart.
	if _prepared_external_root.is_empty():
		return {"ok": true, "root": "", "changed": false}
	var source_root: String = ProjectSettings.globalize_path(_root_dir).simplify_path()
	var destination: String = _prepared_external_root.simplify_path()
	if _storage_path_key(source_root) == _storage_path_key(destination):
		return {"ok": true, "root": destination, "changed": false}
	var parent: String = destination.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent):
		return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.76b3ad3c2b")}
	var writable_error: String = _probe_writable_directory(parent)
	if not writable_error.is_empty():
		return {"ok": false, "error": writable_error}
	var destination_catalog: String = destination.path_join(CATALOG_FILE)
	if DirAccess.dir_exists_absolute(destination):
		if not FileAccess.file_exists(destination_catalog):
			return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.62233fd6bb")}
		var current_prepared_hash: String = FileAccess.get_sha256(destination_catalog).to_lower()
		if not _prepared_external_catalog_sha256.is_empty() and current_prepared_hash != _prepared_external_catalog_sha256:
			return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.59420ecb04")}
	var token: String = AssetId.make_temporary_id("library-finalize")
	var staging: String = parent.path_join(".notlight_library_finalize_%s" % token)
	var backup: String = parent.path_join(".notlight_library_previous_%s" % token)
	if DirAccess.make_dir_recursive_absolute(staging) != OK:
		return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.783d17af00")}
	var copy_result: Dictionary = _copy_directory_tree(source_root, staging)
	if not bool(copy_result.get("ok", false)):
		_delete_directory_absolute(staging)
		return copy_result
	var validation: Dictionary = _validate_library_snapshot(staging)
	if not bool(validation.get("ok", false)):
		_delete_directory_absolute(staging)
		return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.0a01500dd8") % str(validation.get("error", NotLightL10n.text("runtime.assets.asset_library_service.c248a6fec6")))}
	var had_destination: bool = DirAccess.dir_exists_absolute(destination)
	if had_destination and DirAccess.rename_absolute(destination, backup) != OK:
		_delete_directory_absolute(staging)
		return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.dc381d7b4d")}
	if DirAccess.rename_absolute(staging, destination) != OK:
		if had_destination:
			DirAccess.rename_absolute(backup, destination)
		_delete_directory_absolute(staging)
		return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.c9688453a8")}
	var committed_validation: Dictionary = _validate_library_snapshot(destination)
	if not bool(committed_validation.get("ok", false)):
		_delete_directory_absolute(destination)
		if had_destination:
			DirAccess.rename_absolute(backup, destination)
		return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.30859f6ae1")}
	if had_destination:
		_delete_directory_absolute(backup)
	_prepared_external_catalog_sha256 = FileAccess.get_sha256(destination.path_join(CATALOG_FILE)).to_lower()
	return {"ok": true, "root": destination, "changed": true}


func mark_prepared_external_library_activated() -> void:
	_prepared_external_root = ""
	_prepared_external_catalog_sha256 = ""


func import_files(paths: PackedStringArray, folder_id: String = "") -> PackedStringArray:
	_clear_error()
	if not _require_ready():
		return PackedStringArray()
	var safe_folder: String = folder_id
	if safe_folder == FOLDER_ANY:
		safe_folder = ""
	if not catalog.contains_folder(safe_folder):
		_fail(NotLightL10n.text("library.import.error.folder_missing"))
		return PackedStringArray()
	var jobs: PackedStringArray = importer.enqueue_files(paths, safe_folder)
	if jobs.is_empty() and not paths.is_empty() and not importer.get_last_error().is_empty():
		_fail(importer.get_last_error())
	return jobs


func request_import_preflight(paths: PackedStringArray) -> String:
	_clear_error()
	if not _require_ready() or preflight == null:
		if preflight == null:
			_fail(NotLightL10n.text("library.preflight.error.unavailable"))
		return ""
	var request_id: String = preflight.request(paths)
	if request_id.is_empty() and not preflight.get_last_error().is_empty():
		_fail(preflight.get_last_error())
	return request_id


func cancel_import_preflight(request_id: String = "") -> bool:
	return preflight != null and preflight.cancel(request_id)


func import_preflight_results(results: Array, folder_id: String = "") -> PackedStringArray:
	_clear_error()
	if not _require_ready():
		return PackedStringArray()
	var safe_folder: String = "" if folder_id == FOLDER_ANY else folder_id
	if not catalog.contains_folder(safe_folder):
		_fail(NotLightL10n.text("library.import.error.folder_missing"))
		return PackedStringArray()
	var requests: Array[Dictionary] = []
	for value: Variant in results:
		if value is not ImportCandidateResult:
			continue
		var candidate: ImportCandidateResult = value as ImportCandidateResult
		if candidate == null or not candidate.is_importable():
			continue
		requests.append(candidate.to_import_request())
	if requests.is_empty():
		return PackedStringArray()
	if importer == null or requests.size() > importer.remaining_capacity():
		_fail(NotLightL10n.text("library.import.error.queue_capacity"))
		return PackedStringArray()
	var jobs: PackedStringArray = importer.enqueue_preflight_requests(requests, safe_folder)
	if jobs.size() != requests.size():
		_fail(importer.get_last_error() if not importer.get_last_error().is_empty() else NotLightL10n.text("library.import.error.enqueue"))
	return jobs


func import_image(
	image: Image,
	display_name: String = NotLightL10n.text("runtime.assets.asset_library_service.c997c13d4b"),
	folder_id: String = ""
) -> String:
	_clear_error()
	if not _require_ready() or image == null or image.is_empty():
		if image == null or image.is_empty():
			_fail(NotLightL10n.text("runtime.assets.asset_library_service.b5f922a8e6"))
		return ""
	var safe_folder: String = "" if folder_id == FOLDER_ANY else folder_id
	if not catalog.contains_folder(safe_folder):
		_fail(NotLightL10n.text("runtime.assets.asset_library_service.c5441e21f1"))
		return ""
	var temporary_id: String = AssetId.make_temporary_id("clipboard_image")
	var source_path: String = blobs.temp_dir.path_join("%s.png" % temporary_id)
	var save_error: Error = image.save_png(source_path)
	if save_error != OK:
		_fail(NotLightL10n.text("runtime.assets.asset_library_service.9c9d4fa851"))
		return ""
	var clean_name: String = display_name.strip_edges()
	if clean_name.is_empty():
		clean_name = NotLightL10n.text("runtime.assets.asset_library_service.c997c13d4b")
	var job_id: String = importer.enqueue_file(
		source_path,
		safe_folder,
		clean_name,
		"clipboard.png",
		true
	)
	if job_id.is_empty():
		if FileAccess.file_exists(source_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(source_path))
		_fail(NotLightL10n.text("runtime.assets.asset_library_service.bfb2cb0151"))
	return job_id


func create_folder(name: String, parent_id: String = "") -> Dictionary:
	if not _require_ready():
		return {}
	var safe_parent: String = "" if parent_id == FOLDER_ANY else parent_id
	var folder: Dictionary = catalog.create_folder(name, safe_parent)
	if folder.is_empty():
		_fail(catalog.get_last_error())
		return {}
	folders_changed.emit()
	return folder


func rename_folder(folder_id: String, name: String) -> bool:
	if not _require_ready():
		return false
	if not catalog.rename_folder(folder_id, name):
		_fail(catalog.get_last_error())
		return false
	folders_changed.emit()
	return true


func delete_folder(folder_id: String) -> bool:
	if not _require_ready():
		return false
	if not catalog.delete_folder(folder_id):
		_fail(catalog.get_last_error())
		return false
	folders_changed.emit()
	return true


func rename_asset(asset_id: String, name: String) -> bool:
	if not _require_ready():
		return false
	var clean_name: String = name.strip_edges()
	if clean_name.is_empty():
		_fail(NotLightL10n.text("runtime.assets.asset_library_service.32cd490144"))
		return false
	if not catalog.update_asset(asset_id, {"display_name": clean_name}):
		_fail(catalog.get_last_error())
		return false
	library_changed.emit()
	return true


func move_asset(asset_id: String, folder_id: String) -> bool:
	if not _require_ready():
		return false
	var safe_folder: String = "" if folder_id == FOLDER_ANY else folder_id
	if not catalog.contains_folder(safe_folder):
		_fail(NotLightL10n.text("library.import.error.folder_missing"))
		return false
	if not catalog.update_asset(asset_id, {"folder_id": safe_folder}):
		_fail(catalog.get_last_error())
		return false
	library_changed.emit()
	return true


func move_assets(asset_ids: PackedStringArray, folder_id: String) -> bool:
	if not _require_ready():
		return false
	var safe_folder: String = "" if folder_id == FOLDER_ANY else folder_id
	if not catalog.move_assets(asset_ids, safe_folder):
		_fail(catalog.get_last_error())
		return false
	if not asset_ids.is_empty():
		library_changed.emit()
	return true


func delete_assets(asset_ids: PackedStringArray, allow_used: bool = false) -> Dictionary:
	if not _require_ready():
		return {}
	var unique_ids: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	var records: Array[Dictionary] = []
	var used_names: PackedStringArray = PackedStringArray()
	if not allow_used:
		_synchronize_note_embed_references_for_cleanup()
	for asset_id: String in asset_ids:
		if seen.has(asset_id):
			continue
		seen[asset_id] = true
		var asset: Dictionary = catalog.get_asset(asset_id)
		if asset.is_empty():
			_fail(NotLightL10n.text("runtime.assets.asset_library_service.80fc136573"))
			return {}
		if references.is_used(asset_id) and not allow_used:
			used_names.append(str(asset.get("display_name", asset_id)))
		unique_ids.append(asset_id)
		records.append(asset)
	if not used_names.is_empty():
		_fail(NotLightL10n.text("runtime.assets.asset_library_service.bae6b27349") % ", ".join(used_names))
		return {}
	if unique_ids.is_empty():
		return {"removed": 0, "bytes": 0, "blob_delete_failures": 0}
	if not catalog.remove_assets(unique_ids):
		_fail(catalog.get_last_error())
		return {}
	for removed_record: Dictionary in records:
		if int(removed_record.get("kind", AssetKinds.OTHER)) == AssetKinds.NOTE:
			references.remove_note_embed_refs(str(removed_record.get("id", "")))
	var bytes_freed: int = 0
	var blob_delete_failures: int = 0
	for asset: Dictionary in records:
		var removed_id: String = str(asset.get("id", ""))
		blobs.delete_cache_for_asset(removed_id)
		if _delete_blob_if_unreferenced(asset):
			bytes_freed += int(asset.get("byte_size", 0))
		else:
			blob_delete_failures += 1
	library_changed.emit()
	return {
		"removed": unique_ids.size(),
		"bytes": bytes_freed,
		"blob_delete_failures": blob_delete_failures,
	}


func delete_asset(asset_id: String, allow_used: bool = false) -> bool:
	if not _require_ready():
		return false
	var asset: Dictionary = catalog.get_asset(asset_id)
	if asset.is_empty():
		_fail(NotLightL10n.text("runtime.assets.asset_library_service.81b3052c16"))
		return false
	if not allow_used and not references.is_used(asset_id):
		_synchronize_note_embed_references_for_cleanup()
	if references.is_used(asset_id) and not allow_used:
		_fail(NotLightL10n.text("runtime.assets.asset_library_service.cb07faf980"))
		return false
	var ids: PackedStringArray = PackedStringArray([asset_id])
	if not catalog.remove_assets(ids):
		_fail(catalog.get_last_error())
		return false
	if int(asset.get("kind", AssetKinds.OTHER)) == AssetKinds.NOTE:
		references.remove_note_embed_refs(asset_id)
	blobs.delete_cache_for_asset(asset_id)
	_delete_blob_if_unreferenced(asset)
	library_changed.emit()
	return true


func cleanup_unused() -> Dictionary:
	if not _require_ready():
		return {}
	# Cleanup is a destructive explicit operation, so synchronize pinned media
	# references from durable Notes first. Normal editing updates this index through
	# NoteRepository without disk scans; this pass is only a conservative safety net
	# for startup races or notes imported before their background index completed.
	_synchronize_note_embed_references_for_cleanup()
	var removable: Array[Dictionary] = []
	var ids: PackedStringArray = PackedStringArray()
	for asset: Dictionary in catalog.list_assets_readonly():
		var asset_id: String = str(asset.get("id", ""))
		if references.is_used(asset_id):
			continue
		# Notes are canonical user documents. A note without a board portal is still
		# meaningful library content and must never be swept by generic cleanup.
		if int(asset.get("kind", AssetKinds.OTHER)) == AssetKinds.NOTE:
			continue
		removable.append(asset)
		ids.append(asset_id)
	if not ids.is_empty() and not catalog.remove_assets(ids):
		_fail(catalog.get_last_error())
		return {}
	var bytes_freed: int = 0
	var blob_delete_failures: int = 0
	for asset: Dictionary in removable:
		var asset_id: String = str(asset.get("id", ""))
		blobs.delete_cache_for_asset(asset_id)
		if _delete_blob_if_unreferenced(asset):
			bytes_freed += int(asset.get("byte_size", 0))
		else:
			blob_delete_failures += 1
	var orphan_result: Dictionary = _cleanup_orphan_blobs()
	bytes_freed += int(orphan_result.get("bytes", 0))
	if not ids.is_empty() or int(orphan_result.get("removed", 0)) > 0:
		library_changed.emit()
	return {
		"removed": ids.size(),
		"bytes": bytes_freed,
		"orphan_blobs_removed": int(orphan_result.get("removed", 0)),
		"blob_delete_failures": blob_delete_failures + int(orphan_result.get("failures", 0)),
	}


func get_storage_stats(include_disk_scan: bool = false) -> Dictionary:
	if not _initialized:
		return {
			"asset_count": 0,
			"used_count": 0,
			"unused_count": 0,
			"missing_blob_count": -1,
			"folder_count": 0,
			"blob_bytes": 0,
			"active_blob_bytes": 0,
			"primary_blob_bytes": 0,
			"physical_blob_bytes": -1,
			"cache_bytes": -1,
		}

	# Count durable files by relative path instead of by asset row. Media assets
	# may keep original/optimized variants under one stable asset_id, while
	# primary_blob remains the catalogue's canonical/fallback file.
	var durable_paths: Dictionary = {}
	var active_paths: Dictionary = {}
	var primary_paths: Dictionary = {}
	var used_count: int = 0
	var unused_count: int = 0
	var assets: Array[Dictionary] = catalog.list_assets_readonly()
	for asset: Dictionary in assets:
		var asset_id: String = str(asset.get("id", ""))
		if references.is_used(asset_id):
			used_count += 1
		else:
			unused_count += 1

		var primary_relpath: String = str(asset.get("blob_relpath", ""))
		var primary_size: int = maxi(0, int(asset.get("byte_size", 0)))
		_add_path_size(primary_paths, primary_relpath, primary_size)
		_add_path_size(durable_paths, primary_relpath, primary_size)

		var active_relpath: String = primary_relpath
		var active_size: int = primary_size
		var variant_state: Dictionary = _asset_media_variant_state(asset)
		var variants: Dictionary = variant_state.get("variants", {}) as Dictionary
		if not variants.is_empty():
			for raw_variant: Variant in variants.values():
				if raw_variant is Dictionary:
					var variant: Dictionary = raw_variant as Dictionary
					_add_path_size(
						durable_paths,
						str(variant.get("blob_relpath", "")),
						maxi(0, int(variant.get("byte_size", 0)))
					)
			var preferred_name: String = str(variant_state.get("preferred_variant", "original"))
			var preferred_raw: Variant = variants.get(preferred_name, {})
			if preferred_raw is Dictionary:
				var preferred: Dictionary = preferred_raw as Dictionary
				var preferred_relpath: String = str(preferred.get("blob_relpath", ""))
				if not preferred_relpath.is_empty():
					active_relpath = preferred_relpath
					active_size = maxi(0, int(preferred.get("byte_size", 0)))
		_add_path_size(active_paths, active_relpath, active_size)

	var missing_blob_count: int = -1
	if include_disk_scan:
		missing_blob_count = 0
		for relative_path: Variant in durable_paths.keys():
			if not blobs.blob_exists(str(relative_path)):
				missing_blob_count += 1
	return {
		"asset_count": assets.size(),
		"used_count": used_count,
		"unused_count": unused_count,
		"missing_blob_count": missing_blob_count,
		"folder_count": catalog.list_folders().size(),
		"blob_bytes": _sum_path_sizes(durable_paths),
		"active_blob_bytes": _sum_path_sizes(active_paths),
		"primary_blob_bytes": _sum_path_sizes(primary_paths),
		"physical_blob_bytes": blobs.compute_blob_size() if include_disk_scan else -1,
		"cache_bytes": blobs.compute_cache_size() if include_disk_scan else -1,
	}


func get_integrity_report() -> Dictionary:
	if not _require_ready():
		return {}
	var missing_blob_ids: PackedStringArray = PackedStringArray()
	var missing_paths: Dictionary = {}
	for asset: Dictionary in catalog.list_assets_readonly():
		var asset_missing: bool = false
		for relative_path: String in _asset_blob_relpaths(asset):
			if relative_path.is_empty():
				continue
			if not blobs.blob_exists(relative_path):
				missing_paths[relative_path] = true
				asset_missing = true
		if asset_missing:
			missing_blob_ids.append(str(asset.get("id", "")))
	var dangling_reference_ids: PackedStringArray = PackedStringArray()
	for asset_id: String in references.referenced_asset_ids():
		if not catalog.contains_asset(asset_id):
			dangling_reference_ids.append(asset_id)
	var orphan_entries: Array[Dictionary] = _orphan_blob_entries()
	var orphan_bytes: int = 0
	for entry: Dictionary in orphan_entries:
		orphan_bytes += int(entry.get("byte_size", 0))
	return {
		"ok": missing_blob_ids.is_empty() and dangling_reference_ids.is_empty() and orphan_entries.is_empty(),
		"missing_asset_ids": missing_blob_ids,
		"missing_count": missing_paths.size(),
		"dangling_reference_ids": dangling_reference_ids,
		"dangling_reference_count": dangling_reference_ids.size(),
		"orphan_blob_count": orphan_entries.size(),
		"orphan_blob_bytes": orphan_bytes,
	}


func clear_derived_cache() -> Dictionary:
	_clear_error()
	if not _require_ready():
		return {}
	var bytes_before: int = blobs.compute_cache_size()
	if not blobs.clear_cache():
		_fail(blobs.get_last_error())
		return {}
	library_changed.emit()
	return {"bytes": bytes_before}


func refresh_references() -> void:
	if repository == null:
		return
	references.rebuild(repository)
	references_changed.emit()


func folder_path(folder_id: String) -> String:
	if folder_id == FOLDER_ANY:
		return NotLightL10n.text("library.folder.all")
	if folder_id.is_empty():
		return NotLightL10n.text("library.no_folder")
	return catalog.folder_path(folder_id)


func delete_blob_if_unreferenced_path(relative_path: String) -> bool:
	var clean_path: String = relative_path.strip_edges()
	if clean_path.is_empty():
		return true
	if _blob_relpath_is_referenced(clean_path):
		return true
	return blobs.delete_blob(clean_path)


func _delete_blob_if_unreferenced(removed_asset: Dictionary) -> bool:
	var all_paths: PackedStringArray = _asset_blob_relpaths(removed_asset)
	var ok: bool = true
	for relative_path: String in all_paths:
		if relative_path.is_empty() or _blob_relpath_is_referenced(relative_path):
			continue
		if not blobs.delete_blob(relative_path):
			ok = false
	return ok


func _orphan_blob_entries() -> Array[Dictionary]:
	var known_paths: Dictionary = {}
	for asset: Dictionary in catalog.list_assets_readonly():
		for relative_path: String in _asset_blob_relpaths(asset):
			if not relative_path.is_empty():
				known_paths[relative_path] = true
	var result: Array[Dictionary] = []
	for entry: Dictionary in blobs.list_blob_entries():
		if not known_paths.has(str(entry.get("relative_path", ""))):
			result.append(entry)
	return result


func _add_path_size(path_sizes: Dictionary, relative_path: String, byte_size: int) -> void:
	var clean_path: String = relative_path.strip_edges()
	if clean_path.is_empty():
		return
	path_sizes[clean_path] = maxi(int(path_sizes.get(clean_path, 0)), maxi(0, byte_size))


func _sum_path_sizes(path_sizes: Dictionary) -> int:
	var total: int = 0
	for raw_size: Variant in path_sizes.values():
		total += maxi(0, int(raw_size))
	return total


func _asset_blob_relpaths(asset: Dictionary) -> PackedStringArray:
	return AssetDurableVariants.blob_relpaths(asset)


func _asset_media_variant_state(asset: Dictionary) -> Dictionary:
	return AssetDurableVariants.state_from_asset(asset)


func _blob_relpath_is_referenced(relative_path: String) -> bool:
	for remaining: Dictionary in catalog.list_assets_readonly():
		if _asset_blob_relpaths(remaining).has(relative_path):
			return true
	return false


func _synchronize_note_embed_references_for_cleanup() -> void:
	var changed: bool = false
	for asset: Dictionary in catalog.list_assets_readonly():
		if int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.NOTE:
			continue
		var note_id: String = str(asset.get("id", "")).strip_edges()
		var path: String = blobs.resolve_blob_path(str(asset.get("blob_relpath", "")))
		if note_id.is_empty() or path.is_empty() or not FileAccess.file_exists(path):
			continue
		var expected_size: int = int(asset.get("byte_size", -1))
		if expected_size < 0 or expected_size > AssetImportContentValidator.MAX_NOTE_BYTES:
			continue
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null or int(file.get_length()) != expected_size:
			if file != null:
				file.close()
			continue
		var bytes: PackedByteArray = file.get_buffer(expected_size)
		file.close()
		if bytes.size() != expected_size or not AssetImportContentValidator._is_valid_utf8(bytes):
			continue
		var content: String = bytes.get_string_from_utf8()
		var embed_ids: PackedStringArray = _asset_ids_for_embed_hashes(NoteResourceEmbed.extract_hashes(content))
		changed = references.set_note_embed_refs(note_id, embed_ids) or changed
	if changed:
		references_changed.emit()


func _cleanup_orphan_blobs() -> Dictionary:
	var removed: int = 0
	var failures: int = 0
	var bytes_freed: int = 0
	for entry: Dictionary in _orphan_blob_entries():
		var relative_path: String = str(entry.get("relative_path", ""))
		if blobs.delete_blob(relative_path):
			removed += 1
			bytes_freed += int(entry.get("byte_size", 0))
		else:
			failures += 1
	return {"removed": removed, "failures": failures, "bytes": bytes_freed}


func _validate_library_snapshot(root_path: String) -> Dictionary:
	var catalog_path: String = root_path.path_join(CATALOG_FILE)
	var file: FileAccess = FileAccess.open(catalog_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.c80a1c5683")}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.23c6aac851")}
	var document: Dictionary = parsed as Dictionary
	var assets_value: Variant = document.get("assets", [])
	if assets_value is not Array:
		return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.5c9d530a3e")}
	var assets: Array = assets_value as Array
	for raw_asset: Variant in assets:
		if raw_asset is not Dictionary:
			return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.a8e4265ece")}
		var asset: Dictionary = raw_asset as Dictionary
		for relative_path: String in _asset_blob_relpaths(asset):
			if relative_path.is_empty():
				continue
			if not _snapshot_blob_relpath_is_safe(relative_path):
				return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.afa3d9b102") % relative_path}
			if not FileAccess.file_exists(root_path.path_join(relative_path)):
				return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.26cc5f64a8") % relative_path}
		var hash_validation: String = _validate_asset_snapshot_hashes(root_path, asset)
		if not hash_validation.is_empty():
			return {"ok": false, "error": hash_validation}
	return {"ok": true}


func _validate_asset_snapshot_hashes(root_path: String, asset: Dictionary) -> String:
	var primary_relpath: String = str(asset.get("blob_relpath", "")).strip_edges()
	var expected_hash: String = str(asset.get("hash_sha256", "")).strip_edges().to_lower()
	if not primary_relpath.is_empty():
		if not _snapshot_blob_relpath_is_safe(primary_relpath):
			return NotLightL10n.text("runtime.assets.asset_library_service.afa3d9b102") % primary_relpath
		if expected_hash.length() != 64:
			return NotLightL10n.text("runtime.assets.asset_library_service.34b404cae7") % primary_relpath
		var primary_path: String = root_path.path_join(primary_relpath)
		var actual_hash: String = FileAccess.get_sha256(primary_path).to_lower()
		if actual_hash != expected_hash:
			return NotLightL10n.text("runtime.assets.asset_library_service.447483ef3b") % primary_relpath
		var expected_size: int = int(asset.get("byte_size", -1))
		if expected_size < 0 or _file_size_absolute(primary_path) != expected_size:
			return NotLightL10n.text("runtime.assets.asset_library_service.846de2fea5") % primary_relpath
	var metadata_value: Variant = asset.get("metadata", {})
	if metadata_value is not Dictionary:
		return NotLightL10n.text("runtime.assets.asset_library_service.f10a97b6d3")
	var metadata: Dictionary = metadata_value as Dictionary
	for media_namespace: String in AssetDurableVariants.SUPPORTED_NAMESPACES:
		var state_value: Variant = metadata.get(media_namespace, {})
		if state_value is not Dictionary:
			continue
		var variants_value: Variant = (state_value as Dictionary).get("variants", {})
		if variants_value is not Dictionary:
			return NotLightL10n.text("runtime.assets.asset_library_service.ae30276e74")
		for raw_variant: Variant in (variants_value as Dictionary).values():
			if raw_variant is not Dictionary:
				return NotLightL10n.text("runtime.assets.asset_library_service.06d4ea4144")
			var variant: Dictionary = raw_variant as Dictionary
			var relpath: String = str(variant.get("blob_relpath", "")).strip_edges()
			if relpath.is_empty():
				continue
			if not _snapshot_blob_relpath_is_safe(relpath):
				return NotLightL10n.text("runtime.assets.asset_library_service.5e34571f9a") % relpath
			var variant_hash: String = str(variant.get("hash_sha256", "")).strip_edges().to_lower()
			if variant_hash.length() != 64:
				return NotLightL10n.text("runtime.assets.asset_library_service.34b404cae7") % relpath
			var variant_path: String = root_path.path_join(relpath)
			var variant_actual_hash: String = FileAccess.get_sha256(variant_path).to_lower()
			if variant_actual_hash != variant_hash:
				return NotLightL10n.text("runtime.assets.asset_library_service.447483ef3b") % relpath
			var variant_size: int = int(variant.get("byte_size", -1))
			if variant_size >= 0 and _file_size_absolute(variant_path) != variant_size:
				return NotLightL10n.text("runtime.assets.asset_library_service.d9d9ca2711") % relpath
	return ""


func _snapshot_blob_relpath_is_safe(relative_path: String) -> bool:
	var clean: String = relative_path.strip_edges().replace("\\", "/")
	return (
		not clean.is_empty()
		and not clean.begins_with("/")
		and not clean.contains("..")
		and not clean.contains("://")
		and clean.begins_with("blobs/")
	)


func _file_size_absolute(path: String) -> int:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var byte_size: int = int(file.get_length())
	file.close()
	return byte_size


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


func _copy_directory_tree(source: String, destination: String, depth: int = 0) -> Dictionary:
	if depth > 64:
		return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.2e5c70de80")}
	var directory: DirAccess = DirAccess.open(source)
	if directory == null:
		return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.c46e877385")}
	var files_copied: int = 0
	var bytes_copied: int = 0
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			# cache/tmp are derived or transient; skipping them makes a move to an
			# external disk much faster without risking durable media.
			if depth == 0 and (entry == "cache" or entry == "tmp"):
				entry = directory.get_next()
				continue
			var src: String = source.path_join(entry)
			var dst: String = destination.path_join(entry)
			if directory.is_link(entry):
				directory.list_dir_end()
				return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.9d3e5876e2") % entry}
			if directory.current_is_dir():
				var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(dst)
				if mkdir_error != OK:
					directory.list_dir_end()
					return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.2e48e6af7d") % dst}
				var child: Dictionary = _copy_directory_tree(src, dst, depth + 1)
				if not bool(child.get("ok", false)):
					directory.list_dir_end()
					return child
				files_copied += int(child.get("files", 0))
				bytes_copied += int(child.get("bytes", 0))
			else:
				var copy_error: Error = DirAccess.copy_absolute(src, dst)
				if copy_error != OK:
					directory.list_dir_end()
					return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.17ec390df6") % entry}
				if not _files_equal(src, dst):
					directory.list_dir_end()
					return {"ok": false, "error": NotLightL10n.text("runtime.assets.asset_library_service.79bfce6837") % entry}
				files_copied += 1
				var copied: FileAccess = FileAccess.open(dst, FileAccess.READ)
				if copied != null:
					bytes_copied += int(copied.get_length())
					copied.close()
		entry = directory.get_next()
	directory.list_dir_end()
	return {"ok": true, "files": files_copied, "bytes": bytes_copied}


func _path_is_inside(candidate: String, parent: String) -> bool:
	var clean_candidate: String = _storage_path_key(candidate)
	var clean_parent: String = _storage_path_key(parent)
	if clean_candidate.is_empty() or clean_parent.is_empty():
		return false
	var prefix: String = clean_parent + "/"
	return clean_candidate == clean_parent or clean_candidate.begins_with(prefix)


func _storage_path_key(path: String) -> String:
	var clean: String = path.simplify_path().replace("\\", "/").trim_suffix("/")
	return clean.to_lower() if OS.get_name() == "Windows" else clean


func _probe_writable_directory(path: String) -> String:
	var probe_path: String = path.path_join(".notlight_write_probe_%s.tmp" % AssetId.make_temporary_id("storage"))
	var probe: FileAccess = FileAccess.open(probe_path, FileAccess.WRITE)
	if probe == null:
		return NotLightL10n.text("runtime.assets.asset_library_service.81a6fd063c")
	var payload: PackedByteArray = "NotLight storage write probe".to_utf8_buffer()
	if not probe.store_buffer(payload):
		probe.close()
		DirAccess.remove_absolute(probe_path)
		return NotLightL10n.text("runtime.assets.asset_library_service.78c58467f1")
	probe.flush()
	var write_error: Error = probe.get_error()
	probe.close()
	if write_error != OK:
		DirAccess.remove_absolute(probe_path)
		return NotLightL10n.text("runtime.assets.asset_library_service.ce4a02d65f")
	var readback: PackedByteArray = FileAccess.get_file_as_bytes(probe_path)
	DirAccess.remove_absolute(probe_path)
	if readback != payload:
		return NotLightL10n.text("runtime.assets.asset_library_service.17d26a45da")
	return ""


func _delete_directory_absolute(path: String) -> bool:
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
				if not _delete_directory_absolute(child):
					directory.list_dir_end()
					return false
			else:
				if DirAccess.remove_absolute(child) != OK:
					directory.list_dir_end()
					return false
		entry = directory.get_next()
	directory.list_dir_end()
	return DirAccess.remove_absolute(path) == OK


func _on_board_manifest_changed(metadata: Dictionary) -> void:
	if references.set_board_metadata(metadata):
		references_changed.emit()


func _on_board_deleted(board_id: String) -> void:
	if references.remove_board(board_id):
		references_changed.emit()


func _on_preflight_started(request_id: String, total_count: int) -> void:
	import_preflight_started.emit(request_id, total_count)


func _on_preflight_progress(request_id: String, completed_count: int, total_count: int, source_path: String) -> void:
	import_preflight_progress.emit(request_id, completed_count, total_count, source_path)


func _on_preflight_completed(request_id: String, results: Array) -> void:
	import_preflight_completed.emit(request_id, results)


func _on_preflight_cancelled(request_id: String) -> void:
	import_preflight_cancelled.emit(request_id)


func _on_preflight_failed(request_id: String, message: String) -> void:
	_last_error = message
	import_preflight_failed.emit(request_id, message)


func _on_import_queue_changed(pending_count: int) -> void:
	import_queue_changed.emit(pending_count)


func _on_import_progress(job_id: String, source_path: String, progress: float) -> void:
	import_progress.emit(job_id, source_path, progress)


func _on_import_completed(job_id: String, asset_id: String, duplicate: bool) -> void:
	library_changed.emit()
	import_finished.emit(asset_id, duplicate)
	import_job_finished.emit(job_id, asset_id, duplicate)


func _on_import_failed(job_id: String, source_path: String, message: String) -> void:
	import_failed.emit(message)
	import_job_failed.emit(job_id, source_path, message)
	if message == NotLightL10n.text("library.import.error.cancelled"):
		_last_error = message
		return
	_fail(message)


func _require_ready() -> bool:
	if _initialized:
		return true
	_fail(NotLightL10n.text("runtime.assets.asset_library_service.437e4829bf"))
	return false


func _clear_error() -> void:
	_last_error = ""


func _fail(message: String) -> void:
	_last_error = message
	push_error(message)
	library_error.emit(message)
