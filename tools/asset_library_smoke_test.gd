# SPDX-License-Identifier: GPL-3.0-or-later
extends SceneTree

const TEST_ROOT: String = "user://notlight_stage4_asset_library_smoke"


func _initialize() -> void:
	_delete_directory_recursive(TEST_ROOT)
	var blob_store: AssetBlobStore = AssetBlobStore.new()
	_check(blob_store.setup(TEST_ROOT), "blob store setup failed")
	var catalog: AssetCatalog = AssetCatalog.new()
	_check(catalog.setup(TEST_ROOT.path_join("catalog.json")), "catalog setup failed")

	var payload: PackedByteArray = "NotLight Stage 4 asset library smoke payload".to_utf8_buffer()
	var hash_context: HashingContext = HashingContext.new()
	_check(hash_context.start(HashingContext.HASH_SHA256) == OK, "SHA-256 start failed")
	_check(hash_context.update(payload) == OK, "SHA-256 update failed")
	var digest: PackedByteArray = hash_context.finish()
	_check(digest.size() == 32, "SHA-256 digest size mismatch")
	var hash_sha256: String = digest.hex_encode()

	var first_temp: String = blob_store.make_temp_path("first")
	_write_bytes(first_temp, payload)
	var first_commit: Dictionary = blob_store.commit_temp(first_temp, hash_sha256, "bin")
	_check(not first_commit.is_empty(), "first blob commit failed")
	_check(not bool(first_commit.get("reused", true)), "first blob unexpectedly reused")
	var relative_path: String = str(first_commit.get("relative_path", ""))
	_check(blob_store.blob_exists(relative_path), "committed blob is missing")
	_check(blob_store.resolve_blob_path("../catalog.json").is_empty(), "blob path traversal was accepted")

	var folder: Dictionary = catalog.create_folder("Smoke", "")
	_check(not folder.is_empty(), "virtual folder create failed")
	var folder_id: String = str(folder.get("id", ""))
	var asset_id: String = AssetId.make_uuid()
	var record: Dictionary = {
		"id": asset_id,
		"hash_sha256": hash_sha256,
		"blob_relpath": relative_path,
		"display_name": "Smoke asset",
		"original_filename": "smoke.bin",
		"extension": "bin",
		"kind": AssetKinds.OTHER,
		"byte_size": payload.size(),
		"folder_id": folder_id,
		"created_at_unix": int(Time.get_unix_time_from_system()),
		"imported_at_unix": int(Time.get_unix_time_from_system()),
		"metadata": {},
	}
	_check(catalog.add_asset(record), "catalog add failed")
	_check(str(catalog.find_asset_by_hash(hash_sha256).get("id", "")) == asset_id, "hash lookup failed")

	var second_temp: String = blob_store.make_temp_path("second")
	_write_bytes(second_temp, payload)
	var second_commit: Dictionary = blob_store.commit_temp(second_temp, hash_sha256, "bin")
	_check(bool(second_commit.get("reused", false)), "identical content was not physically deduplicated")
	_check(str(second_commit.get("relative_path", "")) == relative_path, "deduplicated blob path changed")

	var duplicate_record: Dictionary = record.duplicate(true)
	duplicate_record["id"] = AssetId.make_uuid()
	_check(not catalog.add_asset(duplicate_record), "catalog accepted a duplicate SHA-256 logical asset")
	_check(catalog.rename_folder(folder_id, "Smoke renamed"), "folder rename failed")
	_check(catalog.update_asset(asset_id, {"display_name": "Renamed asset", "folder_id": ""}), "asset update failed")

	var document: Dictionary = BoardDocumentSchema.make_empty()
	var content: Dictionary = document.get("content", {}) as Dictionary
	content["images"] = [{"entity_id": "1", "asset_id": asset_id}]
	document["content"] = content
	var refs: PackedStringArray = BoardDocumentSchema.collect_asset_references(document)
	_check(refs.size() == 1 and refs[0] == asset_id, "board asset reference collection failed")

	var reference_index: AssetReferenceIndex = AssetReferenceIndex.new()
	var board_metadata: Dictionary = {"id": "board_smoke", "name": "Smoke board", "asset_refs": [asset_id]}
	_check(reference_index.set_board_metadata(board_metadata), "reference index initial update failed")
	_check(reference_index.usage_count(asset_id) == 1, "reference index usage count failed")
	_check(not reference_index.set_board_metadata(board_metadata), "unchanged reference metadata was treated as changed")
	board_metadata["asset_refs"] = []
	_check(reference_index.set_board_metadata(board_metadata), "reference removal update failed")
	_check(reference_index.usage_count(asset_id) == 0, "reference index did not remove stale usage")
	_check(reference_index.remove_board("board_smoke"), "reference index board removal failed")

	var reopened: AssetCatalog = AssetCatalog.new()
	_check(reopened.setup(TEST_ROOT.path_join("catalog.json")), "catalog reopen failed")
	_check(str(reopened.get_asset(asset_id).get("display_name", "")) == "Renamed asset", "catalog roundtrip failed")

	_delete_directory_recursive(TEST_ROOT)
	print("NotLight Stage 4 Asset Library core smoke test passed.")
	quit(0)


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "failed to create smoke temp file")
	file.store_buffer(bytes)
	file.flush()
	file.close()


func _delete_directory_recursive(path: String) -> bool:
	var absolute: String = ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
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
				if not _delete_directory_recursive(child):
					directory.list_dir_end()
					return false
			else:
				if directory.remove(entry) != OK:
					directory.list_dir_end()
					return false
		entry = directory.get_next()
	directory.list_dir_end()
	return DirAccess.remove_absolute(absolute) == OK


func _check(condition: bool, message: String) -> void:
	assert(condition, message)
