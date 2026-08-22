# SPDX-License-Identifier: GPL-3.0-or-later
class_name AssetCatalog
extends RefCounted

const SCHEMA_ID: String = "notlight.asset_catalog"
const SCHEMA_VERSION: int = 2

var _path: String = ""
var _assets: Array[Dictionary] = []
var _folders: Array[Dictionary] = []
var _asset_by_id: Dictionary = {}
var _asset_id_by_hash: Dictionary = {}
var _folder_by_id: Dictionary = {}
var _last_error: String = ""


func setup(path: String) -> bool:
	_path = path
	_clear_error()
	if not _ensure_directory(_path.get_base_dir()):
		return false
	var backup_path: String = "%s.bak" % _path
	if not FileAccess.file_exists(_path) and not FileAccess.file_exists(backup_path):
		_assets.clear()
		_folders.clear()
		_rebuild_indices()
		return _save()
	var source: Dictionary = _read_json(_path)
	var recovered_from_backup: bool = false
	if not source.is_empty() and _catalog_is_future(source):
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.b0c900b4eb"))
		return false
	if not _catalog_is_supported(source):
		var backup: Dictionary = _read_json(backup_path)
		if not backup.is_empty() and _catalog_is_future(backup):
			_fail(NotLightL10n.text("runtime.assets.asset_catalog.fad870b0b2"))
			return false
		if not _catalog_is_supported(backup):
			_fail(NotLightL10n.text("runtime.assets.asset_catalog.553efa9920"))
			return false
		source = backup
		recovered_from_backup = true
	var normalized_changed: bool = _load_from_dictionary(source)
	if (normalized_changed or recovered_from_backup) and not _save():
		return false
	return true


func get_last_error() -> String:
	return _last_error


func list_assets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in _assets:
		result.append(record.duplicate(true))
	return result


func list_assets_readonly() -> Array[Dictionary]:
	# Trusted service-side view: copy only the Array structure, not every Dictionary.
	# Callers must never mutate returned records. Public UI continues to receive deep copies.
	var result: Array[Dictionary] = []
	for record: Dictionary in _assets:
		result.append(record)
	return result


func list_folders() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in _folders:
		result.append(record.duplicate(true))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_name: String = str(left.get("name", "")).to_lower()
		var right_name: String = str(right.get("name", "")).to_lower()
		return left_name.naturalnocasecmp_to(right_name) < 0
	)
	return result


func make_snapshot() -> Dictionary:
	return {
		"schema": SCHEMA_ID,
		"schema_version": SCHEMA_VERSION,
		"assets": list_assets(),
		"folders": list_folders(),
	}


func apply_import_batch(folder_records: Array[Dictionary], asset_records: Array[Dictionary]) -> bool:
	_clear_error()
	if folder_records.is_empty() and asset_records.is_empty():
		return true
	var next_assets: Array[Dictionary] = []
	for asset: Dictionary in _assets:
		next_assets.append(asset.duplicate(true))
	var next_folders: Array[Dictionary] = []
	for folder: Dictionary in _folders:
		next_folders.append(folder.duplicate(true))
	for source_folder: Dictionary in folder_records:
		next_folders.append(_normalize_folder(source_folder))
	for source_asset: Dictionary in asset_records:
		next_assets.append(_normalize_asset(source_asset))
	var validation_error: String = _validate_full_state(next_assets, next_folders)
	if not validation_error.is_empty():
		_fail(validation_error)
		return false
	var previous_assets: Array[Dictionary] = _assets
	var previous_folders: Array[Dictionary] = _folders
	_assets = next_assets
	_folders = next_folders
	_rebuild_indices()
	if not _save():
		_assets = previous_assets
		_folders = previous_folders
		_rebuild_indices()
		return false
	return true


func restore_snapshot(snapshot: Dictionary) -> bool:
	_clear_error()
	if str(snapshot.get("schema", "")) != SCHEMA_ID:
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.b5bf7a1090"))
		return false
	if int(snapshot.get("schema_version", 0)) != SCHEMA_VERSION:
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.a241b4dc16"))
		return false
	var raw_assets: Variant = snapshot.get("assets", [])
	var raw_folders: Variant = snapshot.get("folders", [])
	if raw_assets is not Array or raw_folders is not Array:
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.3cd6920461"))
		return false
	var restored_assets: Array[Dictionary] = []
	for raw_asset: Variant in (raw_assets as Array):
		if raw_asset is not Dictionary:
			_fail(NotLightL10n.text("runtime.assets.asset_catalog.cf1855a527"))
			return false
		restored_assets.append(_normalize_asset(raw_asset as Dictionary))
	var restored_folders: Array[Dictionary] = []
	for raw_folder: Variant in (raw_folders as Array):
		if raw_folder is not Dictionary:
			_fail(NotLightL10n.text("runtime.assets.asset_catalog.982d013a1d"))
			return false
		restored_folders.append(_normalize_folder(raw_folder as Dictionary))
	var validation_error: String = _validate_full_state(restored_assets, restored_folders)
	if not validation_error.is_empty():
		_fail(validation_error)
		return false
	var previous_assets: Array[Dictionary] = _assets
	var previous_folders: Array[Dictionary] = _folders
	_assets = restored_assets
	_folders = restored_folders
	_rebuild_indices()
	if not _save():
		_assets = previous_assets
		_folders = previous_folders
		_rebuild_indices()
		return false
	return true


func contains_asset(asset_id: String) -> bool:
	return _asset_by_id.has(asset_id)


func contains_folder(folder_id: String) -> bool:
	return folder_id.is_empty() or _folder_by_id.has(folder_id)


func get_asset(asset_id: String) -> Dictionary:
	if not _asset_by_id.has(asset_id):
		return {}
	var index: int = int(_asset_by_id[asset_id])
	return _assets[index].duplicate(true)


func get_folder(folder_id: String) -> Dictionary:
	if folder_id.is_empty() or not _folder_by_id.has(folder_id):
		return {}
	var index: int = int(_folder_by_id[folder_id])
	return _folders[index].duplicate(true)


func find_asset_by_hash(hash_sha256: String) -> Dictionary:
	var clean_hash: String = hash_sha256.strip_edges().to_lower()
	if clean_hash.is_empty() or not _asset_id_by_hash.has(clean_hash):
		return {}
	return get_asset(str(_asset_id_by_hash[clean_hash]))


func add_asset(record: Dictionary) -> bool:
	_clear_error()
	var normalized: Dictionary = _normalize_asset(record)
	var asset_id: String = str(normalized.get("id", ""))
	var hash_sha256: String = str(normalized.get("hash_sha256", ""))
	if asset_id.is_empty() or not _is_sha256(hash_sha256):
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.ad1ca42c28"))
		return false
	if not _blob_path_matches_hash(str(normalized.get("blob_relpath", "")), hash_sha256):
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.08fabcfe20"))
		return false
	if _asset_by_id.has(asset_id):
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.5104f38b66"))
		return false
	if int(normalized.get("kind", AssetKinds.OTHER)) != AssetKinds.NOTE and _asset_id_by_hash.has(hash_sha256):
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.32d705b4dc"))
		return false
	var folder_id: String = str(normalized.get("folder_id", ""))
	if not contains_folder(folder_id):
		normalized["folder_id"] = ""
	_assets.push_front(normalized)
	_rebuild_indices()
	if not _save():
		_assets.remove_at(0)
		_rebuild_indices()
		return false
	return true


func repair_blob_location(asset_id: String, relative_path: String, byte_size: int, extension: String) -> bool:
	_clear_error()
	if not _asset_by_id.has(asset_id):
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.85afbd6588"))
		return false
	var clean_path: String = relative_path.strip_edges().replace("\\", "/")
	var stored_hash: String = str(_assets[int(_asset_by_id[asset_id])].get("hash_sha256", ""))
	if not _blob_path_matches_hash(clean_path, stored_hash):
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.6dc0a7ca8f"))
		return false
	var index: int = int(_asset_by_id[asset_id])
	var previous: Dictionary = _assets[index].duplicate(true)
	_assets[index]["blob_relpath"] = clean_path
	_assets[index]["byte_size"] = maxi(0, byte_size)
	_assets[index]["extension"] = extension.strip_edges().to_lower()
	if not _save():
		_assets[index] = previous
		return false
	return true


func replace_asset_blob(
	asset_id: String,
	hash_sha256: String,
	relative_path: String,
	byte_size: int,
	extension: String,
	metadata: Dictionary = {}
) -> bool:
	_clear_error()
	if not _asset_by_id.has(asset_id):
		_fail(NotLightL10n.text("runtime.assets.asset_library_service.81b3052c16"))
		return false
	var clean_hash: String = hash_sha256.strip_edges().to_lower()
	var clean_path: String = relative_path.strip_edges().replace("\\", "/")
	if not _is_sha256(clean_hash) or not _blob_path_matches_hash(clean_path, clean_hash):
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.f6149338a9"))
		return false
	var current_index: int = int(_asset_by_id[asset_id])
	var current_kind: int = int(_assets[current_index].get("kind", AssetKinds.OTHER))
	if current_kind != AssetKinds.NOTE and _asset_id_by_hash.has(clean_hash) and str(_asset_id_by_hash[clean_hash]) != asset_id:
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.16f30fc26f"))
		return false
	var index: int = int(_asset_by_id[asset_id])
	var previous: Dictionary = _assets[index].duplicate(true)
	_assets[index]["hash_sha256"] = clean_hash
	_assets[index]["blob_relpath"] = clean_path
	_assets[index]["byte_size"] = maxi(0, byte_size)
	_assets[index]["extension"] = extension.strip_edges().to_lower()
	if not metadata.is_empty():
		_assets[index]["metadata"] = metadata.duplicate(true)
	_assets[index] = _normalize_asset(_assets[index])
	_rebuild_indices()
	if not _save():
		_assets[index] = previous
		_rebuild_indices()
		return false
	return true


func update_asset(asset_id: String, changes: Dictionary) -> bool:
	_clear_error()
	if not _asset_by_id.has(asset_id):
		_fail(NotLightL10n.text("runtime.assets.asset_library_service.81b3052c16"))
		return false
	var index: int = int(_asset_by_id[asset_id])
	var previous: Dictionary = _assets[index].duplicate(true)
	var next: Dictionary = previous.duplicate(true)
	for key: Variant in changes.keys():
		next[key] = changes[key]
	next["id"] = asset_id
	next["hash_sha256"] = str(previous.get("hash_sha256", ""))
	next["blob_relpath"] = str(previous.get("blob_relpath", ""))
	next["updated_at_unix"] = int(Time.get_unix_time_from_system())
	next = _normalize_asset(next)
	if not contains_folder(str(next.get("folder_id", ""))):
		_fail(NotLightL10n.text("library.import.error.folder_missing"))
		return false
	_assets[index] = next
	_rebuild_indices()
	if not _save():
		_assets[index] = previous
		_rebuild_indices()
		return false
	return true


func move_assets(asset_ids: PackedStringArray, folder_id: String) -> bool:
	_clear_error()
	if not contains_folder(folder_id):
		_fail(NotLightL10n.text("library.import.error.folder_missing"))
		return false
	if asset_ids.is_empty():
		return true
	var unique_ids: Dictionary = {}
	for asset_id: String in asset_ids:
		if asset_id.is_empty() or not _asset_by_id.has(asset_id):
			_fail(NotLightL10n.text("runtime.assets.asset_catalog.3079f1b011"))
			return false
		unique_ids[asset_id] = true
	var previous: Array[Dictionary] = []
	for asset: Dictionary in _assets:
		previous.append(asset.duplicate(true))
	var now: int = int(Time.get_unix_time_from_system())
	for raw_asset_id: Variant in unique_ids.keys():
		var asset_id: String = str(raw_asset_id)
		var index: int = int(_asset_by_id[asset_id])
		_assets[index]["folder_id"] = folder_id
		_assets[index]["updated_at_unix"] = now
		_assets[index] = _normalize_asset(_assets[index])
	_rebuild_indices()
	if not _save():
		_assets = previous
		_rebuild_indices()
		return false
	return true


func remove_assets(asset_ids: PackedStringArray) -> bool:
	_clear_error()
	if asset_ids.is_empty():
		return true
	var remove_set: Dictionary = {}
	for asset_id: String in asset_ids:
		remove_set[asset_id] = true
	var previous: Array[Dictionary] = []
	for asset: Dictionary in _assets:
		previous.append(asset.duplicate(true))
	var kept: Array[Dictionary] = []
	for record: Dictionary in _assets:
		if not remove_set.has(str(record.get("id", ""))):
			kept.append(record)
	_assets = kept
	_rebuild_indices()
	if not _save():
		_assets = previous
		_rebuild_indices()
		return false
	return true


func create_folder(name: String, parent_id: String = "") -> Dictionary:
	_clear_error()
	var clean_name: String = name.strip_edges()
	if clean_name.is_empty():
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.8fe40f777d"))
		return {}
	if not contains_folder(parent_id):
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.2350f25afa"))
		return {}
	if _folder_name_exists(clean_name, parent_id):
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.689ef316a4"))
		return {}
	var now: int = int(Time.get_unix_time_from_system())
	var record: Dictionary = {
		"id": AssetId.make_uuid(),
		"name": clean_name,
		"parent_id": parent_id,
		"created_at_unix": now,
		"updated_at_unix": now,
	}
	_folders.append(record)
	_rebuild_indices()
	if not _save():
		_folders.pop_back()
		_rebuild_indices()
		return {}
	return record.duplicate(true)


func rename_folder(folder_id: String, name: String) -> bool:
	_clear_error()
	if not _folder_by_id.has(folder_id):
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.6ca98be383"))
		return false
	var clean_name: String = name.strip_edges()
	if clean_name.is_empty():
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.8fe40f777d"))
		return false
	var index: int = int(_folder_by_id[folder_id])
	var parent_id: String = str(_folders[index].get("parent_id", ""))
	if _folder_name_exists(clean_name, parent_id, folder_id):
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.689ef316a4"))
		return false
	var previous: Dictionary = _folders[index].duplicate(true)
	_folders[index]["name"] = clean_name
	_folders[index]["updated_at_unix"] = int(Time.get_unix_time_from_system())
	if not _save():
		_folders[index] = previous
		return false
	return true


func delete_folder(folder_id: String) -> bool:
	_clear_error()
	if not _folder_by_id.has(folder_id):
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.6ca98be383"))
		return false
	for folder: Dictionary in _folders:
		if str(folder.get("parent_id", "")) == folder_id:
			_fail(NotLightL10n.text("runtime.assets.asset_catalog.70a435a3b2"))
			return false
	for asset: Dictionary in _assets:
		if str(asset.get("folder_id", "")) == folder_id:
			_fail(NotLightL10n.text("runtime.assets.asset_catalog.9ef3cb1a2b"))
			return false
	var index: int = int(_folder_by_id[folder_id])
	var removed: Dictionary = _folders[index]
	_folders.remove_at(index)
	_rebuild_indices()
	if not _save():
		_folders.insert(index, removed)
		_rebuild_indices()
		return false
	return true


func folder_path(folder_id: String) -> String:
	if folder_id.is_empty():
		return NotLightL10n.text("library.folder.all")
	var names: Array[String] = []
	var cursor: String = folder_id
	var guard: int = 0
	while not cursor.is_empty() and _folder_by_id.has(cursor) and guard < 64:
		var folder: Dictionary = _folders[int(_folder_by_id[cursor])]
		names.push_front(str(folder.get("name", NotLightL10n.text("notes.folder.unnamed"))))
		cursor = str(folder.get("parent_id", ""))
		guard += 1
	return " / ".join(names)


func _load_from_dictionary(source: Dictionary) -> bool:
	_assets.clear()
	_folders.clear()
	var changed: bool = int(source.get("schema_version", 0)) != SCHEMA_VERSION
	var seen_asset_ids: Dictionary = {}
	var seen_hashes: Dictionary = {}
	var raw_assets: Array = source.get("assets", []) as Array
	for raw: Variant in raw_assets:
		if raw is not Dictionary:
			changed = true
			continue
		var asset: Dictionary = _normalize_asset(raw as Dictionary)
		var asset_id: String = str(asset.get("id", ""))
		var hash_sha256: String = str(asset.get("hash_sha256", ""))
		var allows_shared_hash: bool = int(asset.get("kind", AssetKinds.OTHER)) == AssetKinds.NOTE
		if (
			asset_id.is_empty()
			or not _is_sha256(hash_sha256)
			or not _blob_path_matches_hash(str(asset.get("blob_relpath", "")), hash_sha256)
			or seen_asset_ids.has(asset_id)
			or (seen_hashes.has(hash_sha256) and not allows_shared_hash)
		):
			changed = true
			continue
		seen_asset_ids[asset_id] = true
		if not allows_shared_hash:
			seen_hashes[hash_sha256] = true
		_assets.append(asset)

	var seen_folder_ids: Dictionary = {}
	var raw_folders: Array = source.get("folders", []) as Array
	for raw: Variant in raw_folders:
		if raw is not Dictionary:
			changed = true
			continue
		var folder: Dictionary = _normalize_folder(raw as Dictionary)
		var folder_id: String = str(folder.get("id", ""))
		if folder_id.is_empty() or seen_folder_ids.has(folder_id):
			changed = true
			continue
		seen_folder_ids[folder_id] = true
		_folders.append(folder)

	_assets.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("imported_at_unix", 0)) > int(right.get("imported_at_unix", 0))
	)
	_rebuild_indices()
	if _sanitize_folder_hierarchy():
		changed = true
	if _sanitize_asset_folders():
		changed = true
	_rebuild_indices()
	return changed


func _catalog_is_supported(source: Dictionary) -> bool:
	if str(source.get("schema", "")) != SCHEMA_ID:
		return false
	var version: int = int(source.get("schema_version", 0))
	return version > 0 and version <= SCHEMA_VERSION


func _catalog_is_future(source: Dictionary) -> bool:
	return str(source.get("schema", "")) == SCHEMA_ID and int(source.get("schema_version", 0)) > SCHEMA_VERSION


func _folder_name_exists(name: String, parent_id: String, excluding_id: String = "") -> bool:
	var needle: String = name.strip_edges().to_lower()
	for folder: Dictionary in _folders:
		if str(folder.get("id", "")) == excluding_id:
			continue
		if str(folder.get("parent_id", "")) != parent_id:
			continue
		if str(folder.get("name", "")).strip_edges().to_lower() == needle:
			return true
	return false


func _sanitize_folder_hierarchy() -> bool:
	var changed: bool = false
	for index: int in range(_folders.size()):
		var folder_id: String = str(_folders[index].get("id", ""))
		var parent_id: String = str(_folders[index].get("parent_id", ""))
		if parent_id == folder_id or (not parent_id.is_empty() and not _folder_by_id.has(parent_id)):
			_folders[index]["parent_id"] = ""
			changed = true
			continue
		var visited: Dictionary = {}
		visited[folder_id] = true
		var cursor: String = parent_id
		var cyclic: bool = false
		while not cursor.is_empty() and _folder_by_id.has(cursor):
			if visited.has(cursor):
				cyclic = true
				break
			visited[cursor] = true
			var parent: Dictionary = _folders[int(_folder_by_id[cursor])]
			cursor = str(parent.get("parent_id", ""))
		if cyclic:
			_folders[index]["parent_id"] = ""
			changed = true
	return changed


func _sanitize_asset_folders() -> bool:
	var changed: bool = false
	for index: int in range(_assets.size()):
		var folder_id: String = str(_assets[index].get("folder_id", ""))
		if not folder_id.is_empty() and not _folder_by_id.has(folder_id):
			_assets[index]["folder_id"] = ""
			changed = true
	return changed


func _normalize_asset(source: Dictionary) -> Dictionary:
	var now: int = int(Time.get_unix_time_from_system())
	var extension: String = str(source.get("extension", "")).strip_edges().to_lower()
	var fallback_kind: int = AssetImportCapabilities.kind_for_extension(extension)
	if fallback_kind == AssetKinds.OTHER:
		fallback_kind = AssetKinds.from_extension(extension)
	var original_filename: String = str(source.get("original_filename", "")).strip_edges()
	var display_name: String = str(source.get("display_name", original_filename)).strip_edges()
	if display_name.is_empty():
		display_name = original_filename if not original_filename.is_empty() else NotLightL10n.text("library.resource")
	var metadata_value: Variant = source.get("metadata", {})
	var metadata: Dictionary = {}
	if metadata_value is Dictionary:
		metadata = (metadata_value as Dictionary).duplicate(true)
	return {
		"id": str(source.get("id", "")).strip_edges(),
		"hash_sha256": str(source.get("hash_sha256", "")).strip_edges().to_lower(),
		"blob_relpath": str(source.get("blob_relpath", "")).strip_edges(),
		"display_name": display_name,
		"description": _sanitize_description(str(source.get("description", ""))),
		"tags": _sanitize_tags(source.get("tags", [])),
		"original_filename": original_filename,
		"extension": extension,
		"kind": clampi(int(source.get("kind", fallback_kind)), AssetKinds.IMAGE, AssetKinds.NOTE),
		"byte_size": maxi(0, int(source.get("byte_size", 0))),
		"folder_id": str(source.get("folder_id", "")).strip_edges(),
		"created_at_unix": int(source.get("created_at_unix", now)),
		"imported_at_unix": int(source.get("imported_at_unix", now)),
		"updated_at_unix": int(source.get("updated_at_unix", source.get("imported_at_unix", now))),
		"metadata": metadata,
	}


func _sanitize_description(value: String) -> String:
	var clean: String = value.replace("\r\n", "\n").replace("\r", "\n").strip_edges()
	return clean.left(12000)


func _sanitize_tags(raw_tags: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw_tags is not Array and raw_tags is not PackedStringArray:
		return result
	var seen: Dictionary = {}
	for raw_tag: Variant in raw_tags:
		var tag: String = str(raw_tag).strip_edges()
		while tag.begins_with("#"):
			tag = tag.trim_prefix("#").strip_edges()
		if tag.is_empty():
			continue
		tag = tag.left(48)
		var normalized: String = tag.to_lower()
		if seen.has(normalized):
			continue
		seen[normalized] = true
		result.append(tag)
		if result.size() >= 40:
			break
	return result


func _normalize_folder(source: Dictionary) -> Dictionary:
	var now: int = int(Time.get_unix_time_from_system())
	return {
		"id": str(source.get("id", "")).strip_edges(),
		"name": str(source.get("name", NotLightL10n.text("notes.folder.unnamed"))).strip_edges(),
		"parent_id": str(source.get("parent_id", "")).strip_edges(),
		"created_at_unix": int(source.get("created_at_unix", now)),
		"updated_at_unix": int(source.get("updated_at_unix", now)),
	}


func _rebuild_indices() -> void:
	_asset_by_id.clear()
	_asset_id_by_hash.clear()
	_folder_by_id.clear()
	for index: int in range(_assets.size()):
		var asset: Dictionary = _assets[index]
		var asset_id: String = str(asset.get("id", ""))
		var hash_sha256: String = str(asset.get("hash_sha256", ""))
		if not asset_id.is_empty():
			_asset_by_id[asset_id] = index
		if (
			int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.NOTE
			and not hash_sha256.is_empty()
			and not _asset_id_by_hash.has(hash_sha256)
		):
			_asset_id_by_hash[hash_sha256] = asset_id
	for index: int in range(_folders.size()):
		var folder_id: String = str(_folders[index].get("id", ""))
		if not folder_id.is_empty():
			_folder_by_id[folder_id] = index


func _save() -> bool:
	var data: Dictionary = {
		"schema": SCHEMA_ID,
		"schema_version": SCHEMA_VERSION,
		"assets": _assets,
		"folders": _folders,
	}
	return _write_json_atomic(_path, data)


func _write_json_atomic(path: String, data: Dictionary) -> bool:
	var temp_path: String = "%s.tmp" % path
	var backup_path: String = "%s.bak" % path
	if not _write_json_file(temp_path, data):
		return false
	_remove_if_exists(backup_path)
	var had_original: bool = FileAccess.file_exists(path)
	if had_original:
		var backup_error: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup_path))
		if backup_error != OK:
			_remove_if_exists(temp_path)
			_fail(NotLightL10n.text("runtime.assets.asset_catalog.57afa889fd"))
			return false
	var replace_error: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(path))
	if replace_error != OK:
		if had_original and FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(path))
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.49dbe67208"))
		return false
	return true


func _write_json_file(path: String, data: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.eae2ebc0ef"))
		return false
	var write_ok: bool = file.store_string(JSON.stringify(data, "  ", false, true))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if not write_ok or write_error != OK:
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.5820ee5fde"))
		return false
	return true


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		return {}
	return (parsed as Dictionary).duplicate(true)


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	const HEX: String = "0123456789abcdef"
	for index: int in range(value.length()):
		if HEX.find(value.substr(index, 1)) < 0:
			return false
	return true


func _blob_path_matches_hash(relative_path: String, hash_sha256: String) -> bool:
	if not _is_sha256(hash_sha256) or not _is_safe_blob_relative_path(relative_path):
		return false
	var clean: String = relative_path.strip_edges().replace("\\", "/")
	var expected_prefix: String = "blobs/%s/%s/%s" % [hash_sha256.substr(0, 2), hash_sha256.substr(2, 2), hash_sha256]
	return clean == expected_prefix or clean.begins_with("%s." % expected_prefix)


func _is_safe_blob_relative_path(value: String) -> bool:
	var clean: String = value.strip_edges().replace("\\", "/")
	return not clean.is_empty() and clean.begins_with("blobs/") and not clean.contains("..") and not clean.begins_with("/")


func _validate_full_state(assets: Array[Dictionary], folders: Array[Dictionary]) -> String:
	var folder_by_id: Dictionary = {}
	for folder: Dictionary in folders:
		var folder_id: String = str(folder.get("id", "")).strip_edges()
		var folder_name: String = str(folder.get("name", "")).strip_edges()
		if folder_id.is_empty() or folder_name.is_empty():
			return NotLightL10n.text("runtime.assets.asset_catalog.a722d81b20")
		if folder_by_id.has(folder_id):
			return NotLightL10n.text("runtime.assets.asset_catalog.90554c02fa") % folder_id
		folder_by_id[folder_id] = folder
	for folder: Dictionary in folders:
		var folder_id: String = str(folder.get("id", "")).strip_edges()
		var parent_id: String = str(folder.get("parent_id", "")).strip_edges()
		if parent_id == folder_id or (not parent_id.is_empty() and not folder_by_id.has(parent_id)):
			return NotLightL10n.text("runtime.assets.asset_catalog.da55f2206c")
		var visited: Dictionary = {}
		visited[folder_id] = true
		var cursor: String = parent_id
		while not cursor.is_empty():
			if visited.has(cursor):
				return NotLightL10n.text("runtime.assets.asset_catalog.a858af0532")
			visited[cursor] = true
			var parent: Dictionary = folder_by_id[cursor] as Dictionary
			cursor = str(parent.get("parent_id", "")).strip_edges()
	var seen_asset_ids: Dictionary = {}
	var seen_hashes: Dictionary = {}
	for asset: Dictionary in assets:
		var asset_id: String = str(asset.get("id", "")).strip_edges()
		var hash_sha256: String = str(asset.get("hash_sha256", "")).strip_edges().to_lower()
		var blob_relpath: String = str(asset.get("blob_relpath", "")).strip_edges()
		var folder_id: String = str(asset.get("folder_id", "")).strip_edges()
		if asset_id.is_empty() or seen_asset_ids.has(asset_id):
			return NotLightL10n.text("runtime.assets.asset_catalog.89585bd2de")
		var allows_shared_hash: bool = int(asset.get("kind", AssetKinds.OTHER)) == AssetKinds.NOTE
		if not _is_sha256(hash_sha256) or (seen_hashes.has(hash_sha256) and not allows_shared_hash):
			return NotLightL10n.text("runtime.assets.asset_catalog.e5491cf3f6")
		if not _blob_path_matches_hash(blob_relpath, hash_sha256):
			return NotLightL10n.text("runtime.assets.asset_catalog.270b49978c")
		if not folder_id.is_empty() and not folder_by_id.has(folder_id):
			return NotLightL10n.text("runtime.assets.asset_catalog.40b7446652")
		seen_asset_ids[asset_id] = true
		if not allows_shared_hash:
			seen_hashes[hash_sha256] = true
	return ""


func _ensure_directory(path: String) -> bool:
	var absolute: String = ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(absolute):
		return true
	var error: Error = DirAccess.make_dir_recursive_absolute(absolute)
	if error != OK:
		_fail(NotLightL10n.text("runtime.assets.asset_catalog.b5d0612519") % path)
		return false
	return true


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _clear_error() -> void:
	_last_error = ""


func _fail(message: String) -> void:
	_last_error = message
