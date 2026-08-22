# SPDX-License-Identifier: GPL-3.0-or-later
class_name PopplerTools
extends RefCounted

const WINDOWS_RELATIVE_ROOT: String = "tools/poppler/windows"
const WINDOWS_BIN_RELATIVE: String = WINDOWS_RELATIVE_ROOT + "/Library/bin"
const LINUX_BIN_RELATIVE: String = "tools/poppler/linux/bin"
const MACOS_BIN_RELATIVE: String = "tools/poppler/macos/bin"
const BUNDLED_VERSION: String = "26.02.0"


static func pdftoppm_path() -> String:
	return _tool_path("pdftoppm")


static func pdfinfo_path() -> String:
	return _tool_path("pdfinfo")


static func tools_available() -> bool:
	# Never launch a helper from the UI thread just to probe availability. For
	# bundled Windows tools we can validate the files directly; PATH-based
	# backends are verified by PdfRenderWorker when the first real job runs.
	return _tool_candidate_available(pdftoppm_path()) and _tool_candidate_available(pdfinfo_path())


static func version_line() -> String:
	if OS.has_feature("windows"):
		var bundled: String = ProjectSettings.globalize_path(
			"res://" + WINDOWS_BIN_RELATIVE.path_join("pdftoppm.exe")
		)
		var sidecar: String = OS.get_executable_path().get_base_dir().path_join(WINDOWS_BIN_RELATIVE).path_join("pdftoppm.exe")
		if FileAccess.file_exists(bundled) or FileAccess.file_exists(sidecar):
			return "Poppler %s" % BUNDLED_VERSION
	return ""


static func _tool_path(tool_name: String) -> String:
	if OS.has_feature("android") or OS.has_feature("ios"):
		return ""
	var executable: String = tool_name + (".exe" if OS.has_feature("windows") else "")
	var relative_bin: String = WINDOWS_BIN_RELATIVE
	if OS.has_feature("linux"):
		relative_bin = LINUX_BIN_RELATIVE
	elif OS.has_feature("macos"):
		relative_bin = MACOS_BIN_RELATIVE
	for root: String in _runtime_roots(relative_bin):
		var candidate: String = root.path_join(executable)
		if FileAccess.file_exists(candidate):
			return candidate
	# Windows release builds use the pinned sidecar; do not silently report a
	# missing bundle as available merely because a bare executable name exists.
	# Linux/macOS keep a PATH fallback until their pinned bundles are finalized.
	if OS.has_feature("windows"):
		return ""
	return executable


static func _runtime_roots(relative_bin: String) -> PackedStringArray:
	var roots: PackedStringArray = PackedStringArray()
	var project_root: String = ProjectSettings.globalize_path("res://" + relative_bin)
	if not project_root.is_empty():
		roots.append(project_root)
	var app_root: String = OS.get_executable_path().get_base_dir().path_join(relative_bin)
	if not app_root.is_empty() and not roots.has(app_root):
		roots.append(app_root)
	return roots


static func _tool_candidate_available(path: String) -> bool:
	var clean_path: String = path.strip_edges()
	if clean_path.is_empty():
		return false
	if clean_path.is_absolute_path():
		return FileAccess.file_exists(clean_path)
	# A bare executable name intentionally means "resolve through PATH". Its
	# actual executability is checked off the main thread by PdfRenderWorker.
	return true
