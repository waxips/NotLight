# SPDX-License-Identifier: GPL-3.0-or-later
class_name AssetBlobStore
extends RefCounted

var root_dir: String = ""
var blobs_dir: String = ""
var cache_dir: String = ""
var temp_dir: String = ""
var _last_error: String = ""


func setup(library_root: String) -> bool:
	root_dir = library_root
	blobs_dir = root_dir.path_join("blobs")
	cache_dir = root_dir.path_join("cache")
	temp_dir = root_dir.path_join("tmp")
	var required_directories: Array[String] = [root_dir, blobs_dir, cache_dir, temp_dir]
	for path: String in required_directories:
		if not _ensure_directory(path):
			return false
	_cleanup_stale_temp_files()
	return true


func get_last_error() -> String:
	return _last_error


func _cleanup_stale_temp_files() -> void:
	var directory: DirAccess = DirAccess.open(temp_dir)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		var is_managed_temp: bool = entry.ends_with(".part") or (
			entry.begins_with("clipboard_image_") and entry.ends_with(".png")
		)
		if not directory.current_is_dir() and is_managed_temp:
			directory.remove(entry)
		entry = directory.get_next()
	directory.list_dir_end()


func make_temp_path(job_id: String) -> String:
	return temp_dir.path_join("%s.part" % _safe_component(job_id))


func commit_temp(temp_path: String, hash_sha256: String, extension: String) -> Dictionary:
	_clear_error()
	var clean_hash: String = hash_sha256.strip_edges().to_lower()
	if not _validate_commit_input(temp_path, clean_hash):
		return {}
	# The blob store is an integrity boundary. Normal callers never get to skip
	# verification merely because the destination path is content-addressed.
	if FileAccess.get_sha256(temp_path).to_lower() != clean_hash:
		_fail(NotLightL10n.text("runtime.assets.asset_blob_store.ab02de8c6e"))
		return {}
	return _commit_verified_temp(temp_path, clean_hash, extension)


func commit_preverified_temp(
	temp_path: String,
	hash_sha256: String,
	extension: String,
	expected_byte_size: int
) -> Dictionary:
	# This narrow path exists for internal staging pipelines that computed SHA-256
	# incrementally before commit. It deliberately avoids hashing a large file a
	# second time on the main thread. Never expose this method through ModuleContext
	# or use it for arbitrary user-provided paths.
	_clear_error()
	var clean_hash: String = hash_sha256.strip_edges().to_lower()
	if not _validate_commit_input(temp_path, clean_hash):
		return {}
	if not _is_managed_preverified_temp_path(temp_path):
		_fail(NotLightL10n.text("runtime.assets.asset_blob_store.3c9881414d"))
		return {}
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.READ)
	if file == null:
		_fail(NotLightL10n.text("runtime.assets.asset_blob_store.86b6c5011a"))
		return {}
	var actual_byte_size: int = int(file.get_length())
	file.close()
	if expected_byte_size < 0 or actual_byte_size != expected_byte_size:
		_fail(NotLightL10n.text("runtime.assets.asset_blob_store.bda0a427c0"))
		return {}
	return _commit_verified_temp(temp_path, clean_hash, extension)


func _validate_commit_input(temp_path: String, clean_hash: String) -> bool:
	if not _is_sha256(clean_hash):
		_fail(NotLightL10n.text("runtime.assets.asset_blob_store.db890b0134"))
		return false
	if not FileAccess.file_exists(temp_path):
		_fail(NotLightL10n.text("runtime.assets.asset_blob_store.f6aba70a9d"))
		return false
	return true


func _is_managed_preverified_temp_path(temp_path: String) -> bool:
	# Preverified commits are intentionally narrower than normal imports. The
	# caller must use make_temp_path(), so a stale/malicious absolute path can
	# never be promoted merely by pairing it with a claimed digest.
	var clean_temp_root: String = temp_dir.replace("\\", "/").trim_suffix("/")
	var clean_base_dir: String = temp_path.get_base_dir().replace("\\", "/").trim_suffix("/")
	return (
		not clean_temp_root.is_empty()
		and clean_base_dir == clean_temp_root
		and temp_path.get_file().ends_with(".part")
	)


func _commit_verified_temp(temp_path: String, clean_hash: String, extension: String) -> Dictionary:
	var relative: String = _blob_relative_path(clean_hash, extension)
	var destination: String = root_dir.path_join(relative)
	if not _ensure_directory(destination.get_base_dir()):
		return {}
	if FileAccess.file_exists(destination):
		if FileAccess.get_sha256(destination).to_lower() == clean_hash:
			remove_temp(temp_path)
			return {"relative_path": relative, "reused": true, "repaired": false}
		# A file at a content-addressed path with different bytes is corrupted.
		# Replace it atomically with the already verified import payload. The repair
		# is intentionally kept even if a later package transaction rolls back: it
		# restores an invariant that the existing catalog already depended on.
		var backup: String = "%s.corrupt-%s" % [destination, AssetId.make_temporary_id("blob")]
		while FileAccess.file_exists(backup):
			backup = "%s.corrupt-%s" % [destination, AssetId.make_temporary_id("blob")]
		var backup_error: Error = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(destination),
			ProjectSettings.globalize_path(backup)
		)
		if backup_error != OK:
			_fail(NotLightL10n.text("runtime.assets.asset_blob_store.0359e5ad47"))
			return {}
		var repair_error: Error = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(temp_path),
			ProjectSettings.globalize_path(destination)
		)
		if repair_error != OK:
			var restore_error: Error = DirAccess.rename_absolute(
				ProjectSettings.globalize_path(backup),
				ProjectSettings.globalize_path(destination)
			)
			if restore_error != OK:
				_fail(NotLightL10n.text("runtime.assets.asset_blob_store.01a83c6f4c"))
			else:
				_fail(NotLightL10n.text("runtime.assets.asset_blob_store.1a1ae6aaa7"))
			return {}
		DirAccess.remove_absolute(ProjectSettings.globalize_path(backup))
		return {"relative_path": relative, "reused": true, "repaired": true}
	var error: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temp_path),
		ProjectSettings.globalize_path(destination)
	)
	if error != OK:
		_fail(NotLightL10n.text("runtime.assets.asset_blob_store.48afafa6f7"))
		return {}
	return {"relative_path": relative, "reused": false, "repaired": false}


func resolve_blob_path(relative_path: String) -> String:
	var clean: String = relative_path.strip_edges().replace("\\", "/")
	if clean.is_empty() or clean.begins_with("/") or clean.contains(".."):
		return ""
	if not clean.begins_with("blobs/"):
		return ""
	return root_dir.path_join(clean)


func blob_exists(relative_path: String) -> bool:
	var path: String = resolve_blob_path(relative_path)
	return not path.is_empty() and FileAccess.file_exists(path)


func delete_blob(relative_path: String) -> bool:
	_clear_error()
	var path: String = resolve_blob_path(relative_path)
	if path.is_empty() or not FileAccess.file_exists(path):
		return true
	var error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if error != OK:
		_fail(NotLightL10n.text("runtime.assets.asset_blob_store.43a0947de1") % relative_path)
		return false
	return true


func delete_cache_for_asset(asset_id: String) -> bool:
	var path: String = cache_dir.path_join(_safe_component(asset_id))
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		return true
	return _delete_directory_recursive(path)


func cache_path_for_asset(asset_id: String) -> String:
	return cache_dir.path_join(_safe_component(asset_id))


func remove_temp(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func list_blob_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_collect_blob_entries(blobs_dir, "blobs", result)
	return result


func compute_blob_size() -> int:
	return _directory_size(blobs_dir)


func compute_cache_size() -> int:
	return _directory_size(cache_dir)


func clear_cache() -> bool:
	_clear_error()
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(cache_dir)):
		if not _delete_directory_recursive(cache_dir):
			_fail(NotLightL10n.text("runtime.assets.asset_blob_store.5d8235f7b1"))
			return false
	return _ensure_directory(cache_dir)


func _blob_relative_path(hash_sha256: String, extension: String) -> String:
	var safe_extension: String = _safe_extension(extension)
	var file_name: String = hash_sha256
	if not safe_extension.is_empty():
		file_name += ".%s" % safe_extension
	return "blobs/%s/%s/%s" % [hash_sha256.substr(0, 2), hash_sha256.substr(2, 2), file_name]


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	const HEX: String = "0123456789abcdef"
	for index: int in range(value.length()):
		if HEX.find(value.substr(index, 1)) < 0:
			return false
	return true


func _safe_extension(value: String) -> String:
	var clean: String = value.strip_edges().to_lower()
	var result: String = ""
	const ALLOWED: String = "abcdefghijklmnopqrstuvwxyz0123456789"
	for index: int in range(clean.length()):
		var character: String = clean.substr(index, 1)
		if ALLOWED.contains(character):
			result += character
	return result.substr(0, 12)


func _safe_component(value: String) -> String:
	var clean: String = value.strip_edges()
	var result: String = ""
	const ALLOWED: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
	for index: int in range(clean.length()):
		var character: String = clean.substr(index, 1)
		if ALLOWED.contains(character):
			result += character
	return result if not result.is_empty() else "item"


func _collect_blob_entries(path: String, relative_prefix: String, output: Array[Dictionary]) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child_path: String = path.path_join(entry)
			var child_relative: String = relative_prefix.path_join(entry)
			if directory.current_is_dir():
				_collect_blob_entries(child_path, child_relative, output)
			else:
				var file: FileAccess = FileAccess.open(child_path, FileAccess.READ)
				if file != null:
					output.append({"relative_path": child_relative, "byte_size": int(file.get_length())})
					file.close()
		entry = directory.get_next()
	directory.list_dir_end()


func _directory_size(path: String) -> int:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return 0
	var total: int = 0
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child: String = path.path_join(entry)
			# Managed storage must never follow a symlink/junction outside its root.
			if directory.is_link(entry):
				entry = directory.get_next()
				continue
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


func _delete_directory_recursive(path: String) -> bool:
	var absolute: String = ProjectSettings.globalize_path(path) if path.begins_with("user://") or path.begins_with("res://") else path
	if not DirAccess.dir_exists_absolute(absolute):
		return true
	var parent: DirAccess = DirAccess.open(absolute.get_base_dir())
	var entry_name: String = absolute.get_file()
	if parent != null and not entry_name.is_empty() and parent.is_link(entry_name):
		return DirAccess.remove_absolute(absolute) == OK
	var directory: DirAccess = DirAccess.open(absolute)
	if directory == null:
		return true
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child: String = absolute.path_join(entry)
			# Delete a link itself; never recurse through its target.
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


func _ensure_directory(path: String) -> bool:
	var absolute: String = ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(absolute):
		return true
	var error: Error = DirAccess.make_dir_recursive_absolute(absolute)
	if error != OK:
		_fail(NotLightL10n.text("runtime.assets.asset_blob_store.f0fa80edf3") % path)
		return false
	return true


func _clear_error() -> void:
	_last_error = ""


func _fail(message: String) -> void:
	_last_error = message
