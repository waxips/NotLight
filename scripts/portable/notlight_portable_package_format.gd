# SPDX-License-Identifier: GPL-3.0-or-later
class_name NotLightPortablePackageFormat
extends RefCounted

# NotLight portable exchange container.
#
# The format is deliberately stream-friendly instead of ZIP-based: media files are
# already compressed in most real projects, while FileAccess lets us copy and hash
# multi-gigabyte payloads without loading the whole package into memory.
#
# Layout (little-endian, Godot FileAccess default):
#   8 bytes   ASCII magic "NLTPKG01"
#   u32       container version
#   u64       UTF-8 manifest byte length
#   32 bytes  SHA-256(manifest bytes)
#   N bytes   JSON manifest
#   ...       raw payload bytes in manifest["payloads"] order
#
# The JSON manifest never contains executable Variant objects. Importers must treat
# it as untrusted data and only materialize payloads through the validated offsets.

const MAGIC_TEXT: String = "NLTPKG01"
const CONTAINER_VERSION: int = 1
const MANIFEST_SCHEMA: String = "notlight.portable_package"
const MANIFEST_SCHEMA_VERSION: int = 2
const PACKAGE_TYPE_BOARD: String = "board"
const PACKAGE_TYPE_LIBRARY: String = "library"
const PACKAGE_TYPE_MODULE: String = "module"
const BOARD_EXTENSION: String = "notlight-board"
const LIBRARY_EXTENSION: String = "notlight-library"
const MODULE_EXTENSION: String = "notlight-module"
const FIXED_HEADER_BYTES: int = 8 + 4 + 8 + 32
const MAX_MANIFEST_BYTES: int = 64 * 1024 * 1024
const MAX_PAYLOAD_COUNT: int = 100000
const MAX_PAYLOAD_KEY_LENGTH: int = 256
const COPY_CHUNK_BYTES: int = 1024 * 1024


static func inspect(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.c6493f089f"))
	var result: Dictionary = _inspect_open_file(file)
	file.close()
	if not bool(result.get("ok", false)):
		return result
	result["path"] = path
	return result


static func verify_payload_hashes(path: String) -> Dictionary:
	# Final-file verification is intentionally separate from inspect(): callers that
	# only need metadata stay cheap, while durable export paths can pay one bounded
	# sequential read to prove that the committed container still matches every
	# manifest digest. No payload is materialized in memory.
	var inspected: Dictionary = inspect(path)
	if not bool(inspected.get("ok", false)):
		return inspected
	var payloads_value: Variant = inspected.get("payloads", [])
	if payloads_value is not Array:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.158ddc0a64"))
	var input: FileAccess = FileAccess.open(path, FileAccess.READ)
	if input == null:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.963353c825"))
	for raw_descriptor: Variant in (payloads_value as Array):
		if raw_descriptor is not Dictionary:
			input.close()
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.8952683ad4"))
		var descriptor: Dictionary = raw_descriptor as Dictionary
		var offset: int = int(descriptor.get("offset", -1))
		var byte_size: int = int(descriptor.get("byte_size", -1))
		var expected_hash: String = str(descriptor.get("sha256", "")).to_lower()
		if offset < 0 or byte_size < 0 or not _is_sha256(expected_hash):
			input.close()
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.4cff71b752"))
		input.seek(offset)
		if input.get_position() != offset:
			input.close()
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.53e8c5aade"))
		var hash: HashingContext = HashingContext.new()
		if hash.start(HashingContext.HASH_SHA256) != OK:
			input.close()
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.c16ad6b337"))
		var remaining: int = byte_size
		while remaining > 0:
			var chunk_size: int = mini(COPY_CHUNK_BYTES, remaining)
			var chunk: PackedByteArray = input.get_buffer(chunk_size)
			if chunk.size() != chunk_size or hash.update(chunk) != OK:
				input.close()
				return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.1d39c7dbc2"))
			remaining -= chunk_size
		var digest: PackedByteArray = hash.finish()
		if digest.size() != 32 or digest.hex_encode() != expected_hash:
			input.close()
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.67fbe32d1f") % str(descriptor.get("key", "")))
	input.close()
	return {"ok": true, "payload_count": (payloads_value as Array).size()}


static func write_package(destination_path: String, manifest_base: Dictionary, payload_sources: Array[Dictionary]) -> Dictionary:
	var clean_destination: String = destination_path.strip_edges()
	if clean_destination.is_empty():
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_service.476490b47a"))
	if payload_sources.size() > MAX_PAYLOAD_COUNT:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.6b69490542"))
	var prepared_payloads: Array[Dictionary] = []
	var seen_keys: Dictionary = {}
	for source: Dictionary in payload_sources:
		var key: String = str(source.get("key", "")).strip_edges()
		var source_path: String = str(source.get("source_path", "")).strip_edges()
		if _same_file_path(source_path, clean_destination):
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.4c9c8e0589"))
		if key.is_empty() or key.length() > MAX_PAYLOAD_KEY_LENGTH or seen_keys.has(key):
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.72f6efe45d"))
		if source_path.is_empty() or not FileAccess.file_exists(source_path):
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.549e5178d8") % source_path)
		var opened: FileAccess = FileAccess.open(source_path, FileAccess.READ)
		if opened == null:
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.1b97b95a98") % source_path)
		var byte_size: int = int(opened.get_length())
		opened.close()
		var computed_hash: String = FileAccess.get_sha256(source_path).to_lower()
		if not _is_sha256(computed_hash):
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.607310cc03") % source_path)
		var expected_hash: String = str(source.get("expected_sha256", "")).strip_edges().to_lower()
		if not expected_hash.is_empty() and expected_hash != computed_hash:
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.073e3ad1fa") % source_path)
		var descriptor: Dictionary = {
			"key": key,
			"byte_size": byte_size,
			"sha256": computed_hash,
		}
		var purpose: String = str(source.get("purpose", "")).strip_edges()
		if not purpose.is_empty():
			descriptor["purpose"] = purpose
		prepared_payloads.append(descriptor)
		seen_keys[key] = true

	var manifest: Dictionary = manifest_base.duplicate(true)
	manifest["schema"] = MANIFEST_SCHEMA
	manifest["schema_version"] = MANIFEST_SCHEMA_VERSION
	manifest["container_version"] = CONTAINER_VERSION
	manifest["payloads"] = prepared_payloads
	var manifest_text: String = JSON.stringify(manifest, "  ", false, true)
	var manifest_bytes: PackedByteArray = manifest_text.to_utf8_buffer()
	if manifest_bytes.is_empty() or manifest_bytes.size() > MAX_MANIFEST_BYTES:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.3f3154c273"))
	var manifest_digest: PackedByteArray = _hash_bytes(manifest_bytes)
	if manifest_digest.size() != 32:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.ea7ab87149"))

	var parent_directory: String = clean_destination.get_base_dir()
	if not _ensure_directory(parent_directory):
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.666ae1a71e"))
	var temporary_path: String = _make_unused_sibling_path(clean_destination, "part")
	if temporary_path.is_empty():
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.caa984d658"))
	var output: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if output == null:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.b206850da6"))
	output.big_endian = false
	var write_ok: bool = true
	write_ok = output.store_buffer(MAGIC_TEXT.to_utf8_buffer()) and write_ok
	write_ok = output.store_32(CONTAINER_VERSION) and write_ok
	write_ok = output.store_64(manifest_bytes.size()) and write_ok
	write_ok = output.store_buffer(manifest_digest) and write_ok
	write_ok = output.store_buffer(manifest_bytes) and write_ok
	if not write_ok:
		output.close()
		_remove_file_if_exists(temporary_path)
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.6934cd3570"))

	for index: int in range(payload_sources.size()):
		var source_record: Dictionary = payload_sources[index]
		var source_path: String = str(source_record.get("source_path", ""))
		var prepared: Dictionary = prepared_payloads[index] as Dictionary
		var expected_size: int = int(prepared.get("byte_size", 0))
		var expected_hash: String = str(prepared.get("sha256", ""))
		var copy_result: Dictionary = _append_file(output, source_path, expected_size, expected_hash)
		if not bool(copy_result.get("ok", false)):
			output.close()
			_remove_file_if_exists(temporary_path)
			return copy_result
	output.flush()
	var output_error: Error = output.get_error()
	output.close()
	if output_error != OK:
		_remove_file_if_exists(temporary_path)
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.9a2df585e6"))

	var commit_result: Dictionary = _commit_atomic_file(temporary_path, clean_destination)
	if not bool(commit_result.get("ok", false)):
		_remove_file_if_exists(temporary_path)
		return commit_result
	return {
		"ok": true,
		"path": clean_destination,
		"payload_count": prepared_payloads.size(),
		"byte_size": _file_size(clean_destination),
	}


static func materialize_payloads(package_info: Dictionary, requested_keys: Dictionary, staging_directory: String) -> Dictionary:
	if not bool(package_info.get("ok", false)):
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.4320308947"))
	var package_path: String = str(package_info.get("path", "")).strip_edges()
	var payloads_value: Variant = package_info.get("payloads", [])
	if package_path.is_empty() or payloads_value is not Array:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.158ddc0a64"))
	var payloads: Array = payloads_value as Array
	if not _ensure_directory(staging_directory):
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.34c7f78d1e"))
	var input: FileAccess = FileAccess.open(package_path, FileAccess.READ)
	if input == null:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.45634c654c"))
	var staged: Dictionary = {}
	for descriptor_index: int in range(payloads.size()):
		var raw_descriptor: Variant = payloads[descriptor_index]
		if raw_descriptor is not Dictionary:
			input.close()
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.5c7efa530a"))
		var descriptor: Dictionary = raw_descriptor as Dictionary
		var key: String = str(descriptor.get("key", ""))
		var byte_size: int = int(descriptor.get("byte_size", -1))
		var expected_hash: String = str(descriptor.get("sha256", "")).to_lower()
		var offset: int = int(descriptor.get("offset", -1))
		if key.is_empty() or byte_size < 0 or offset < 0 or not _is_sha256(expected_hash):
			input.close()
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.0b342d8984") % key)
		input.seek(offset)
		var output: FileAccess = null
		var output_path: String = ""
		if requested_keys.has(key):
			output_path = staging_directory.path_join("payload_%06d_%s.part" % [descriptor_index, expected_hash.substr(0, 16)])
			_remove_file_if_exists(output_path)
			output = FileAccess.open(output_path, FileAccess.WRITE)
			if output == null:
				input.close()
				return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.97e1220c4a"))
		var hash: HashingContext = HashingContext.new()
		if hash.start(HashingContext.HASH_SHA256) != OK:
			if output != null:
				output.close()
			input.close()
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.ee086542ba"))
		var remaining: int = byte_size
		var payload_ok: bool = true
		while remaining > 0:
			var chunk_size: int = mini(COPY_CHUNK_BYTES, remaining)
			var chunk: PackedByteArray = input.get_buffer(chunk_size)
			if chunk.size() != chunk_size:
				payload_ok = false
				break
			if hash.update(chunk) != OK:
				payload_ok = false
				break
			if output != null and not output.store_buffer(chunk):
				payload_ok = false
				break
			remaining -= chunk.size()
		var digest: PackedByteArray = hash.finish()
		var output_error: Error = OK
		if output != null:
			output.flush()
			output_error = output.get_error()
			output.close()
		if output_error != OK:
			payload_ok = false
		if not payload_ok or digest.size() != 32 or digest.hex_encode() != expected_hash:
			if not output_path.is_empty():
				_remove_file_if_exists(output_path)
			input.close()
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.4ae5cded2d") % key)
		if not output_path.is_empty():
			staged[key] = output_path
	input.close()
	for raw_key: Variant in requested_keys.keys():
		var requested_key: String = str(raw_key)
		if not staged.has(requested_key):
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_service.725c54edb2") % requested_key)
	return {"ok": true, "files": staged}


static func cleanup_directory(path: String) -> void:
	_delete_directory_recursive(path)


static func _inspect_open_file(file: FileAccess) -> Dictionary:
	file.big_endian = false
	if file.get_length() < FIXED_HEADER_BYTES:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.bd7748d7c2"))
	var magic: PackedByteArray = file.get_buffer(8)
	if magic.get_string_from_ascii() != MAGIC_TEXT:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.2c6e894814"))
	var container_version: int = file.get_32()
	if container_version != CONTAINER_VERSION:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.9ef21a0a95") % container_version)
	var manifest_size: int = file.get_64()
	if manifest_size <= 0 or manifest_size > MAX_MANIFEST_BYTES:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.f51bee179b"))
	if manifest_size > file.get_length() - FIXED_HEADER_BYTES:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.59f820c9ab"))
	var expected_manifest_hash: PackedByteArray = file.get_buffer(32)
	if expected_manifest_hash.size() != 32:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.87f9773d25"))
	var manifest_bytes: PackedByteArray = file.get_buffer(manifest_size)
	if manifest_bytes.size() != manifest_size:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.ce2a0e3a82"))
	var computed_manifest_hash: PackedByteArray = _hash_bytes(manifest_bytes)
	if computed_manifest_hash != expected_manifest_hash:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.bd9f6b3e18"))
	var parsed: Variant = JSON.parse_string(manifest_bytes.get_string_from_utf8())
	if parsed is not Dictionary:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.72c8b2d413"))
	var manifest: Dictionary = parsed as Dictionary
	if str(manifest.get("schema", "")) != MANIFEST_SCHEMA:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.169dd54947"))
	var manifest_version: int = int(manifest.get("schema_version", 0))
	if manifest_version <= 0:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.5bfcbc9c00"))
	if manifest_version > MANIFEST_SCHEMA_VERSION:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.a71fe6a840"))
	if int(manifest.get("container_version", 0)) != CONTAINER_VERSION:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.ee72e50453"))
	var package_type: String = str(manifest.get("package_type", ""))
	if package_type != PACKAGE_TYPE_BOARD and package_type != PACKAGE_TYPE_LIBRARY and package_type != PACKAGE_TYPE_MODULE:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.3c2b8195ac"))
	var payloads_value: Variant = manifest.get("payloads", [])
	if payloads_value is not Array:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.aedf06f575"))
	var raw_payloads: Array = payloads_value as Array
	if raw_payloads.size() > MAX_PAYLOAD_COUNT:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.6b69490542"))
	var payloads: Array[Dictionary] = []
	var seen_keys: Dictionary = {}
	var payload_offset: int = FIXED_HEADER_BYTES + manifest_size
	for raw_descriptor: Variant in raw_payloads:
		if raw_descriptor is not Dictionary:
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.5c7efa530a"))
		var source: Dictionary = raw_descriptor as Dictionary
		var key: String = str(source.get("key", "")).strip_edges()
		var byte_size: int = int(source.get("byte_size", -1))
		var hash_sha256: String = str(source.get("sha256", "")).strip_edges().to_lower()
		if key.is_empty() or key.length() > MAX_PAYLOAD_KEY_LENGTH or seen_keys.has(key) or byte_size < 0 or not _is_sha256(hash_sha256):
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.ddd355a8ad"))
		if payload_offset > file.get_length() or byte_size > file.get_length() - payload_offset:
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.c4a7ddca05") % key)
		var normalized: Dictionary = source.duplicate(true)
		normalized["key"] = key
		normalized["byte_size"] = byte_size
		normalized["sha256"] = hash_sha256
		normalized["offset"] = payload_offset
		payloads.append(normalized)
		seen_keys[key] = true
		payload_offset += byte_size
	if payload_offset != file.get_length():
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.084327e75b"))
	return {
		"ok": true,
		"manifest": manifest.duplicate(true),
		"package_type": package_type,
		"payloads": payloads,
		"payload_by_key": _payload_index(payloads),
	}


static func _payload_index(payloads: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for descriptor: Dictionary in payloads:
		result[str(descriptor.get("key", ""))] = descriptor.duplicate(true)
	return result


static func _append_file(output: FileAccess, source_path: String, expected_size: int, expected_hash: String) -> Dictionary:
	var input: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if input == null:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.79d0435e90") % source_path)
	if int(input.get_length()) != expected_size:
		input.close()
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.32d0017333") % source_path)
	var hash: HashingContext = HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256) != OK:
		input.close()
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.ab59d7769e"))
	while input.get_position() < input.get_length():
		var remaining: int = int(input.get_length() - input.get_position())
		var chunk_size: int = mini(COPY_CHUNK_BYTES, remaining)
		var chunk: PackedByteArray = input.get_buffer(chunk_size)
		if chunk.size() != chunk_size or hash.update(chunk) != OK or not output.store_buffer(chunk):
			input.close()
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.38582622b2") % source_path)
	input.close()
	var digest: PackedByteArray = hash.finish()
	if digest.size() != 32 or digest.hex_encode() != expected_hash:
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.32d0017333") % source_path)
	return {"ok": true}


static func _commit_atomic_file(temporary_path: String, destination_path: String) -> Dictionary:
	# Keep the previous export until the newly committed container has been opened
	# again and every payload SHA-256 has been verified from its final path. This
	# makes replacement transactional even if a filesystem reports a successful
	# rename after a damaged write.
	var backup_path: String = _make_unused_sibling_path(destination_path, "bak")
	if backup_path.is_empty():
		return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.f6eb87ad19"))
	var had_destination: bool = FileAccess.file_exists(destination_path)
	if had_destination:
		var backup_error: Error = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(destination_path),
			ProjectSettings.globalize_path(backup_path)
		)
		if backup_error != OK:
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.dfb8285688"))
	var commit_error: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary_path),
		ProjectSettings.globalize_path(destination_path)
	)
	if commit_error != OK:
		return _restore_export_backup_after_failure(
			destination_path,
			backup_path,
			had_destination,
			NotLightL10n.text("runtime.portable.notlight_portable_package_format.26155ef13e")
		)
	var verification: Dictionary = verify_payload_hashes(destination_path)
	if not bool(verification.get("ok", false)):
		var verification_error: String = str(verification.get("error", NotLightL10n.text("runtime.portable.notlight_portable_package_format.8a99f475db")))
		return _restore_export_backup_after_failure(
			destination_path,
			backup_path,
			had_destination,
			NotLightL10n.text("runtime.portable.notlight_portable_package_format.9a934608a7") % verification_error
		)
	if had_destination:
		_remove_file_if_exists(backup_path)
	return {"ok": true}


static func _restore_export_backup_after_failure(
	destination_path: String,
	backup_path: String,
	had_destination: bool,
	message: String
) -> Dictionary:
	_remove_file_if_exists(destination_path)
	if had_destination and FileAccess.file_exists(backup_path):
		var restore_error: Error = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(backup_path),
			ProjectSettings.globalize_path(destination_path)
		)
		if restore_error != OK:
			return _error(NotLightL10n.text("runtime.portable.notlight_portable_package_format.2dba2f9426") % message)
	return _error(message)



static func _file_size(path: String) -> int:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var byte_size: int = int(file.get_length())
	file.close()
	return byte_size


static func _hash_bytes(bytes: PackedByteArray) -> PackedByteArray:
	var hash: HashingContext = HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256) != OK:
		return PackedByteArray()
	if hash.update(bytes) != OK:
		return PackedByteArray()
	return hash.finish()


static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	const HEX: String = "0123456789abcdef"
	for index: int in range(value.length()):
		if HEX.find(value.substr(index, 1)) < 0:
			return false
	return true


static func _same_file_path(left: String, right: String) -> bool:
	var clean_left: String = left.strip_edges()
	var clean_right: String = right.strip_edges()
	if clean_left.is_empty() or clean_right.is_empty():
		return false
	var absolute_left: String = ProjectSettings.globalize_path(clean_left).simplify_path()
	var absolute_right: String = ProjectSettings.globalize_path(clean_right).simplify_path()
	if OS.get_name() == "Windows":
		return absolute_left.to_lower() == absolute_right.to_lower()
	return absolute_left == absolute_right


static func _ensure_directory(path: String) -> bool:
	var clean: String = path.strip_edges()
	if clean.is_empty():
		clean = "."
	var absolute: String = ProjectSettings.globalize_path(clean) if clean.begins_with("user://") or clean.begins_with("res://") else clean
	if DirAccess.dir_exists_absolute(absolute):
		return true
	return DirAccess.make_dir_recursive_absolute(absolute) == OK


static func _make_unused_sibling_path(base_path: String, suffix: String) -> String:
	for _attempt: int in range(16):
		var candidate: String = "%s.%s-%s" % [base_path, suffix, AssetId.make_temporary_id("package")]
		if not FileAccess.file_exists(candidate) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(candidate)):
			return candidate
	return ""


static func _remove_file_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _delete_directory_recursive(path: String) -> bool:
	var absolute: String = ProjectSettings.globalize_path(path) if path.begins_with("user://") or path.begins_with("res://") else path
	if not DirAccess.dir_exists_absolute(absolute):
		return true
	var parent_path: String = absolute.get_base_dir()
	var entry_name: String = absolute.get_file()
	var parent: DirAccess = DirAccess.open(parent_path)
	if parent != null and not entry_name.is_empty() and parent.is_link(entry_name):
		return DirAccess.remove_absolute(absolute) == OK
	var directory: DirAccess = DirAccess.open(absolute)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child: String = absolute.path_join(entry)
			# Never recurse through a symlink/junction found in temporary storage.
			# A local attacker or a manually modified user:// tree must not be able
			# to turn cleanup into deletion outside NotLight's staging directory.
			if directory.is_link(entry):
				if DirAccess.remove_absolute(child) != OK:
					directory.list_dir_end()
					return false
			elif directory.current_is_dir():
				if not _delete_directory_recursive(child):
					directory.list_dir_end()
					return false
			else:
				if DirAccess.remove_absolute(child) != OK:
					directory.list_dir_end()
					return false
		entry = directory.get_next()
	directory.list_dir_end()
	return DirAccess.remove_absolute(absolute) == OK


static func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
