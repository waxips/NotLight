# SPDX-License-Identifier: GPL-3.0-or-later
@tool
extends EditorExportPlugin

# Windows sidecars (Poppler, qpdf, Typst/MiTeX and FFmpeg CLI) must remain
# ordinary files beside the exported application. Godot's resource filesystem
# intentionally ignores some of these folders via .gdignore, so the export
# plugin delegates the physical packaging and smoke test to the project-owned
# PowerShell script instead of trying to copy the sidecars through FileAccess.

var _target_path: String = ""
var _windows_export: bool = false


func _get_name() -> String:
	return "NotLightRuntimeSidecars"


func _export_begin(features: PackedStringArray, _is_debug: bool, path: String, _flags: int) -> void:
	_target_path = _absolute_export_path(path)
	_windows_export = features.has("windows") and _target_path.get_extension().to_lower() == "exe"
	if _windows_export:
		print(NotLightL10n.text("export.runtime.windows_detected") % _target_path)


func _export_file(_path: String, _type: String, _features: PackedStringArray) -> void:
	pass


func _export_end() -> void:
	if not _windows_export:
		_reset()
		return

	var destination_root: String = _target_path.get_base_dir().simplify_path()
	if destination_root.is_empty():
		push_error(NotLightL10n.text("export.runtime.resolve_directory_failed"))
		_reset()
		return

	# This is intentionally a physical filesystem operation. Runtime sidecars are
	# excluded from Godot's resource scan with .gdignore and cannot live in PCK.
	if OS.get_name() != "Windows":
		push_error(NotLightL10n.text("export.runtime.windows_host_required"))
		_reset()
		return

	var project_root: String = ProjectSettings.globalize_path("res://").simplify_path()
	var package_script: String = project_root.path_join("tools/package_export_runtime_windows.ps1").simplify_path()
	var arguments: PackedStringArray = PackedStringArray([
		"-NoProfile",
		"-ExecutionPolicy",
		"Bypass",
		"-File",
		package_script,
		"-BuildDir",
		destination_root,
		"-ExportedExe",
		_target_path,
	])
	var output: Array = []
	print(NotLightL10n.text("export.runtime.finalizing"))
	var exit_code: int = OS.execute("powershell.exe", arguments, output, true, false)
	for line: Variant in output:
		var text: String = str(line).strip_edges()
		if not text.is_empty():
			print(text)
	if exit_code != 0:
		push_error(NotLightL10n.text("export.runtime.finalization_failed") % exit_code)
	else:
		print(NotLightL10n.text("export.runtime.ready"))
	_reset()


func _absolute_export_path(path: String) -> String:
	var clean_path: String = path.strip_edges()
	if clean_path.is_absolute_path():
		return clean_path.simplify_path()
	var project_root: String = ProjectSettings.globalize_path("res://").simplify_path()
	return project_root.path_join(clean_path).simplify_path()


func _reset() -> void:
	_target_path = ""
	_windows_export = false
