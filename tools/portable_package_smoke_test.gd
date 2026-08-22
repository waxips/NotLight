# SPDX-License-Identifier: GPL-3.0-or-later
extends SceneTree

const TEST_ROOT: String = "user://notlight_portable_package_smoke"


func _initialize() -> void:
	_delete_directory_recursive(TEST_ROOT)
	_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_ROOT)) == OK, "portable smoke root setup failed")
	_test_stream_container_roundtrip()
	_test_blob_store_repairs_corrupt_content_addressed_file()
	_delete_directory_recursive(TEST_ROOT)
	print("NotLight portable package and blob-integrity smoke test passed.")
	quit(0)


func _test_stream_container_roundtrip() -> void:
	var first_path: String = TEST_ROOT.path_join("first.bin")
	var second_path: String = TEST_ROOT.path_join("second.bin")
	var first_bytes: PackedByteArray = "portable payload alpha".to_utf8_buffer()
	var second_bytes: PackedByteArray = "portable payload beta".to_utf8_buffer()
	_write_bytes(first_path, first_bytes)
	_write_bytes(second_path, second_bytes)
	var package_path: String = TEST_ROOT.path_join("roundtrip.notlight-library")
	var manifest: Dictionary = {
		"package_type": NotLightPortablePackageFormat.PACKAGE_TYPE_LIBRARY,
		"library": {
			"catalog_schema": AssetCatalog.SCHEMA_ID,
			"catalog_schema_version": AssetCatalog.SCHEMA_VERSION,
		},
		"folders": [],
		"assets": [],
	}
	var payload_sources: Array[Dictionary] = [
		{"key": "alpha", "source_path": first_path, "expected_sha256": FileAccess.get_sha256(first_path)},
		{"key": "beta", "source_path": second_path, "expected_sha256": FileAccess.get_sha256(second_path)},
	]
	var written: Dictionary = NotLightPortablePackageFormat.write_package(package_path, manifest, payload_sources)
	_check(bool(written.get("ok", false)), "portable package write failed")
	var inspected: Dictionary = NotLightPortablePackageFormat.inspect(package_path)
	_check(bool(inspected.get("ok", false)), "portable package inspect failed")
	_check(str(inspected.get("package_type", "")) == NotLightPortablePackageFormat.PACKAGE_TYPE_LIBRARY, "portable package type mismatch")
	var payloads: Array = inspected.get("payloads", []) as Array
	_check(payloads.size() == 2, "portable package payload count mismatch")

	var staging: String = TEST_ROOT.path_join("staging")
	var materialized: Dictionary = NotLightPortablePackageFormat.materialize_payloads(inspected, {"beta": true}, staging)
	_check(bool(materialized.get("ok", false)), "portable package materialization failed")
	var files: Dictionary = materialized.get("files", {}) as Dictionary
	_check(files.size() == 1 and files.has("beta"), "portable package materialized unexpected payloads")
	var staged_beta: String = str(files.get("beta", ""))
	_check(FileAccess.get_sha256(staged_beta) == FileAccess.get_sha256(second_path), "materialized payload hash mismatch")
	NotLightPortablePackageFormat.cleanup_directory(staging)

	var empty_package_path: String = TEST_ROOT.path_join("empty.notlight-library")
	var empty_written: Dictionary = NotLightPortablePackageFormat.write_package(empty_package_path, manifest, [])
	_check(bool(empty_written.get("ok", false)), "empty portable package write failed")
	var empty_inspected: Dictionary = NotLightPortablePackageFormat.inspect(empty_package_path)
	_check(bool(empty_inspected.get("ok", false)), "empty portable package inspect failed")
	_check((empty_inspected.get("payloads", []) as Array).is_empty(), "empty portable package unexpectedly contains payloads")

	var manifest_corrupted_path: String = TEST_ROOT.path_join("manifest_corrupted.notlight-library")
	var manifest_corrupted_bytes: PackedByteArray = FileAccess.get_file_as_bytes(package_path)
	_check(manifest_corrupted_bytes.size() > NotLightPortablePackageFormat.FIXED_HEADER_BYTES, "portable package is too small for manifest corruption test")
	manifest_corrupted_bytes[NotLightPortablePackageFormat.FIXED_HEADER_BYTES] = int(manifest_corrupted_bytes[NotLightPortablePackageFormat.FIXED_HEADER_BYTES]) ^ 0x01
	_write_bytes(manifest_corrupted_path, manifest_corrupted_bytes)
	_check(not bool(NotLightPortablePackageFormat.inspect(manifest_corrupted_path).get("ok", false)), "corrupted manifest escaped SHA-256 verification")

	var truncated_path: String = TEST_ROOT.path_join("truncated.notlight-library")
	var truncated_bytes: PackedByteArray = FileAccess.get_file_as_bytes(package_path)
	_check(truncated_bytes.size() > 1, "portable package is too small for truncation test")
	truncated_bytes.resize(truncated_bytes.size() - 1)
	_write_bytes(truncated_path, truncated_bytes)
	_check(not bool(NotLightPortablePackageFormat.inspect(truncated_path).get("ok", false)), "truncated payload escaped package length verification")

	var corrupted_path: String = TEST_ROOT.path_join("corrupted.notlight-library")
	var package_bytes: PackedByteArray = FileAccess.get_file_as_bytes(package_path)
	_check(not package_bytes.is_empty(), "portable package bytes unexpectedly empty")
	package_bytes[package_bytes.size() - 1] = int(package_bytes[package_bytes.size() - 1]) ^ 0x01
	_write_bytes(corrupted_path, package_bytes)
	var corrupted_info: Dictionary = NotLightPortablePackageFormat.inspect(corrupted_path)
	_check(bool(corrupted_info.get("ok", false)), "payload corruption should not alter the already-hashed manifest")
	var corrupted_materialization: Dictionary = NotLightPortablePackageFormat.materialize_payloads(
		corrupted_info,
		{"alpha": true},
		TEST_ROOT.path_join("corrupted_staging")
	)
	_check(not bool(corrupted_materialization.get("ok", false)), "corrupted unrequested payload escaped checksum verification")
	NotLightPortablePackageFormat.cleanup_directory(TEST_ROOT.path_join("corrupted_staging"))

	var self_overwrite: Dictionary = NotLightPortablePackageFormat.write_package(first_path, manifest, payload_sources)
	_check(not bool(self_overwrite.get("ok", false)), "portable exporter accepted destination equal to a payload source")


func _test_blob_store_repairs_corrupt_content_addressed_file() -> void:
	var store_root: String = TEST_ROOT.path_join("blob_store")
	var store: AssetBlobStore = AssetBlobStore.new()
	_check(store.setup(store_root), "blob store setup failed")
	var payload: PackedByteArray = "known-good-content-addressed-payload".to_utf8_buffer()
	var first_temp: String = store.make_temp_path("initial")
	_write_bytes(first_temp, payload)
	var expected_hash: String = FileAccess.get_sha256(first_temp)
	var initial: Dictionary = store.commit_temp(first_temp, expected_hash, "bin")
	_check(not initial.is_empty() and not bool(initial.get("reused", true)), "initial content-addressed commit failed")
	var relative_path: String = str(initial.get("relative_path", ""))
	var destination: String = store.resolve_blob_path(relative_path)
	_check(not destination.is_empty(), "committed blob path did not resolve")
	_write_bytes(destination, "corrupted-local-bytes".to_utf8_buffer())
	_check(FileAccess.get_sha256(destination) != expected_hash, "blob corruption setup failed")

	var repair_temp: String = store.make_temp_path("repair")
	_write_bytes(repair_temp, payload)
	var repaired: Dictionary = store.commit_temp(repair_temp, expected_hash, "bin")
	_check(bool(repaired.get("reused", false)), "repair should preserve the existing content-addressed location")
	_check(bool(repaired.get("repaired", false)), "corrupted content-addressed blob was not reported as repaired")
	_check(FileAccess.get_sha256(destination) == expected_hash, "corrupted content-addressed blob was not repaired")


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var parent: String = path.get_base_dir()
	if not parent.is_empty() and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(parent)):
		_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(parent)) == OK, "failed to create smoke parent directory")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "failed to open smoke file for writing")
	_check(file.store_buffer(bytes), "failed to write smoke bytes")
	file.flush()
	_check(file.get_error() == OK, "failed to flush smoke file")
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
