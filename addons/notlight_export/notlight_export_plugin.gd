# SPDX-License-Identifier: GPL-3.0-or-later
@tool
extends EditorPlugin

var _runtime_export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	_runtime_export_plugin = preload("res://addons/notlight_export/notlight_export_runtime_plugin.gd").new()
	add_export_plugin(_runtime_export_plugin)


func _exit_tree() -> void:
	if _runtime_export_plugin != null:
		remove_export_plugin(_runtime_export_plugin)
		_runtime_export_plugin = null
