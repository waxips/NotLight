# SPDX-License-Identifier: GPL-3.0-or-later
class_name QpdfTools
extends RefCounted

const WINDOWS_RELATIVE_ROOT: String = "tools/qpdf/windows"
const LINUX_RELATIVE_ROOT: String = "tools/qpdf/linux"
const MACOS_RELATIVE_ROOT: String = "tools/qpdf/macos"
const BUNDLED_VERSION: String = "12.4.0"
const EXPECTED_ARCHIVE_NAME: String = "qpdf-12.4.0-msvc64.zip"
const EXPECTED_ARCHIVE_SHA256: String = "5bcb25353f7e6df92b5625dbcfe52a5c34a2a5fba2d1a8b98b8a6a0972c3ff72"
const PRESET_LOSSLESS: String = "lossless"
const PRESET_BALANCED: String = "balanced"
const MAX_SEARCH_DEPTH: int = 4


static func qpdf_path() -> String:
	if OS.has_feature("android") or OS.has_feature("ios"):
		return ""
	var executable_name: String = "qpdf.exe" if OS.has_feature("windows") else "qpdf"
	for root: String in _desktop_roots():
		var found: String = _find_executable_recursive(root, executable_name, 0)
		if not found.is_empty():
			return found
	return executable_name


static func bundled_tools_available() -> bool:
	if not OS.has_feature("windows"):
		return false
	var path: String = qpdf_path()
	return path.is_absolute_path() and FileAccess.file_exists(path)


static func candidate_available() -> bool:
	var path: String = qpdf_path().strip_edges()
	if path.is_empty():
		return false
	if path.is_absolute_path():
		return FileAccess.file_exists(path)
	# Bare executable names are allowed as a developer fallback. Actual PATH
	# resolution is verified by the first non-blocking --version job.
	return true


static func version_arguments() -> PackedStringArray:
	return PackedStringArray(["--version"])


static func check_arguments(pdf_path: String) -> PackedStringArray:
	return PackedStringArray([_native_path(pdf_path), "--check"])


static func optimize_arguments(source_path: String, output_path: String, preset: String) -> PackedStringArray:
	var arguments: PackedStringArray = PackedStringArray([
		_native_path(source_path),
		"--compress-streams=y",
		"--decode-level=generalized",
		"--recompress-flate",
		"--compression-level=9",
		"--object-streams=generate",
	])
	if normalize_preset(preset) == PRESET_BALANCED:
		arguments.append("--optimize-images")
		arguments.append("--jpeg-quality=90")
	arguments.append(_native_path(output_path))
	return arguments


static func normalize_preset(preset: String) -> String:
	return PRESET_BALANCED if preset.strip_edges().to_lower() == PRESET_BALANCED else PRESET_LOSSLESS


static func preset_is_lossy(preset: String) -> bool:
	return normalize_preset(preset) == PRESET_BALANCED


static func parse_version_line(output: String) -> String:
	for raw_line: String in output.split("\n", false):
		var line: String = raw_line.strip_edges()
		if not line.is_empty():
			return line
	return ""


static func parse_version_value(output: String) -> String:
	for raw_token: String in output.replace("\r", " ").replace("\n", " ").split(" ", false):
		var token: String = raw_token.strip_edges()
		if _looks_like_version(token):
			return token
	return ""


static func bundled_version_matches(output: String) -> bool:
	return parse_version_value(output) == BUNDLED_VERSION


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


static func _windows_roots() -> PackedStringArray:
	return _runtime_roots(WINDOWS_RELATIVE_ROOT)


static func _desktop_roots() -> PackedStringArray:
	if OS.has_feature("windows"):
		return _windows_roots()
	if OS.has_feature("linux"):
		return _runtime_roots(LINUX_RELATIVE_ROOT)
	if OS.has_feature("macos"):
		return _runtime_roots(MACOS_RELATIVE_ROOT)
	return PackedStringArray()


static func _runtime_roots(relative_root: String) -> PackedStringArray:
	var roots: PackedStringArray = PackedStringArray()
	var project_root: String = ProjectSettings.globalize_path("res://" + relative_root)
	if not project_root.is_empty():
		roots.append(project_root)
	var executable_root: String = OS.get_executable_path().get_base_dir().path_join(relative_root)
	if not executable_root.is_empty() and not roots.has(executable_root):
		roots.append(executable_root)
	return roots


static func _find_executable_recursive(directory_path: String, file_name: String, depth: int) -> String:
	if depth > MAX_SEARCH_DEPTH or not DirAccess.dir_exists_absolute(directory_path):
		return ""
	var direct_candidate: String = directory_path.path_join(file_name)
	if FileAccess.file_exists(direct_candidate):
		return direct_candidate
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		return ""
	var child_directories: PackedStringArray = PackedStringArray()
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != ".." and not directory.is_link(entry) and directory.current_is_dir():
			child_directories.append(directory_path.path_join(entry))
		entry = directory.get_next()
	directory.list_dir_end()
	child_directories.sort()
	for child: String in child_directories:
		var nested: String = _find_executable_recursive(child, file_name, depth + 1)
		if not nested.is_empty():
			return nested
	return ""


static func _native_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path
