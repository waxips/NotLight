# SPDX-License-Identifier: GPL-3.0-or-later
class_name TypstMiTexTools
extends RefCounted

const WINDOWS_RELATIVE_ROOT: String = "tools/typst/windows"
const LINUX_RELATIVE_ROOT: String = "tools/typst/linux"
const MACOS_RELATIVE_ROOT: String = "tools/typst/macos"
const PACKAGE_RELATIVE_ROOT: String = "tools/typst/packages"
const BUNDLED_TYPST_VERSION: String = "0.15.1"
const MITEX_VERSION: String = "0.2.7"
const EXPECTED_WINDOWS_ARCHIVE_NAME: String = "typst-x86_64-pc-windows-msvc.zip"
const PACKAGE_NAMESPACE: String = "local"
const PACKAGE_NAME: String = "mitex"
const PACKAGE_METADATA_NAME: String = ".NOTLIGHT_MITEX_PACKAGE_INFO.json"
const MAX_SEARCH_DEPTH: int = 4
const MAX_METADATA_BYTES: int = 16 * 1024
const REQUIRED_PACKAGE_FILES: PackedStringArray = [
	"typst.toml",
	"LICENSE",
	"lib.typ",
	"mitex.typ",
	"mitex.wasm",
	"specs/mod.typ",
]


static func typst_path() -> String:
	if OS.has_feature("android") or OS.has_feature("ios"):
		return ""
	var relative_root: String = ""
	var executable_name: String = "typst"
	if OS.has_feature("windows"):
		relative_root = WINDOWS_RELATIVE_ROOT
		executable_name = "typst.exe"
	elif OS.has_feature("linux"):
		relative_root = LINUX_RELATIVE_ROOT
	elif OS.has_feature("macos"):
		relative_root = MACOS_RELATIVE_ROOT
	if not relative_root.is_empty():
		for root: String in _runtime_roots(relative_root):
			var found: String = _find_file_recursive(root, executable_name, 0)
			if not found.is_empty():
				return found
		# Windows release/runtime uses an explicitly pinned sidecar. Linux/macOS
		# retain a PATH fallback until their pinned distributions are finalized.
		if OS.has_feature("windows"):
			return ""
	return "typst"


static func package_root() -> String:
	for root: String in _runtime_roots(PACKAGE_RELATIVE_ROOT):
		var package: String = root.path_join(PACKAGE_NAMESPACE).path_join(PACKAGE_NAME).path_join(MITEX_VERSION)
		if _package_directory_valid(package):
			return root
	return ""


static func mitex_package_path() -> String:
	var root: String = package_root()
	if root.is_empty():
		return ""
	return root.path_join(PACKAGE_NAMESPACE).path_join(PACKAGE_NAME).path_join(MITEX_VERSION)


static func candidate_available() -> bool:
	var executable: String = typst_path().strip_edges()
	if executable.is_empty():
		return false
	if executable.is_absolute_path() and not FileAccess.file_exists(executable):
		return false
	return not mitex_package_path().is_empty()


static func package_content_digest(package_path: String) -> String:
	var metadata: Dictionary = package_metadata(package_path)
	var digest: String = str(metadata.get("content_digest_sha256", "")).strip_edges().to_lower()
	return digest if _is_sha256(digest) else ""


static func package_metadata(package_path: String) -> Dictionary:
	if package_path.is_empty() or not _package_files_present(package_path):
		return {}
	var metadata_path: String = package_path.path_join(PACKAGE_METADATA_NAME)
	var file: FileAccess = FileAccess.open(metadata_path, FileAccess.READ)
	if file == null or int(file.get_length()) <= 0 or int(file.get_length()) > MAX_METADATA_BYTES:
		if file != null:
			file.close()
		return {}
	var text: String = file.get_buffer(int(file.get_length())).get_string_from_utf8()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		return {}
	var metadata: Dictionary = parsed as Dictionary
	if str(metadata.get("schema", "")) != "notlight.mitex-package-provenance":
		return {}
	if str(metadata.get("package", "")) != PACKAGE_NAME or str(metadata.get("version", "")) != MITEX_VERSION:
		return {}
	return metadata


static func version_arguments() -> PackedStringArray:
	return PackedStringArray(["--version"])


static func compile_arguments(
	input_path: String,
	output_svg_path: String,
	job_root: String,
	local_package_root: String,
	isolated_package_cache: String
) -> PackedStringArray:
	return PackedStringArray([
		"compile",
		"--format", "svg",
		"--root", _native_path(job_root),
		"--package-path", _native_path(local_package_root),
		"--package-cache-path", _native_path(isolated_package_cache),
		"--ignore-system-fonts",
		"--creation-timestamp", "0",
		"--jobs", "1",
		"--diagnostic-format", "short",
		_native_path(input_path),
		_native_path(output_svg_path),
	])


static func parse_version_value(output: String) -> String:
	for raw_token: String in output.replace("\r", " ").replace("\n", " ").split(" ", false):
		var token: String = raw_token.strip_edges().trim_prefix("v")
		if _looks_like_version(token):
			return token
	return ""


static func expected_local_import() -> String:
	return "@%s/%s:%s" % [PACKAGE_NAMESPACE, PACKAGE_NAME, MITEX_VERSION]


static func _package_directory_valid(directory_path: String) -> bool:
	if not _package_files_present(directory_path):
		return false
	var metadata: Dictionary = package_metadata(directory_path)
	var digest: String = str(metadata.get("content_digest_sha256", "")).strip_edges().to_lower()
	return _is_sha256(digest)


static func _package_files_present(directory_path: String) -> bool:
	if directory_path.is_empty() or not DirAccess.dir_exists_absolute(directory_path):
		return false
	for relative_path: String in REQUIRED_PACKAGE_FILES:
		if not FileAccess.file_exists(directory_path.path_join(relative_path)):
			return false
	return FileAccess.file_exists(directory_path.path_join(PACKAGE_METADATA_NAME))


static func _looks_like_version(value: String) -> bool:
	if value.is_empty() or value.count(".") < 2:
		return false
	for index: int in range(value.length()):
		var codepoint: int = value.unicode_at(index)
		if codepoint == 46:
			continue
		if codepoint < 48 or codepoint > 57:
			return false
	return true


static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in range(value.length()):
		var codepoint: int = value.unicode_at(index)
		var decimal: bool = codepoint >= 48 and codepoint <= 57
		var lower_hex: bool = codepoint >= 97 and codepoint <= 102
		if not decimal and not lower_hex:
			return false
	return true


static func _runtime_roots(relative_root: String) -> PackedStringArray:
	var roots: PackedStringArray = PackedStringArray()
	var project_root: String = ProjectSettings.globalize_path("res://" + relative_root)
	if not project_root.is_empty():
		roots.append(project_root)
	var app_root: String = OS.get_executable_path().get_base_dir().path_join(relative_root)
	if not app_root.is_empty() and not roots.has(app_root):
		roots.append(app_root)
	return roots


static func _find_file_recursive(directory_path: String, file_name: String, depth: int) -> String:
	if depth > MAX_SEARCH_DEPTH or not DirAccess.dir_exists_absolute(directory_path):
		return ""
	var direct_candidate: String = directory_path.path_join(file_name)
	if FileAccess.file_exists(direct_candidate):
		return direct_candidate
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		return ""
	var children: PackedStringArray = PackedStringArray()
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != ".." and not directory.is_link(entry) and directory.current_is_dir():
			children.append(directory_path.path_join(entry))
		entry = directory.get_next()
	directory.list_dir_end()
	children.sort()
	for child: String in children:
		var nested: String = _find_file_recursive(child, file_name, depth + 1)
		if not nested.is_empty():
			return nested
	return ""


static func _native_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path
