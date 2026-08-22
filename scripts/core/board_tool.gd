# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardTool
extends RefCounted

var tool_id: StringName = StringName()
var display_name: String = ""
var cursor_shape: Control.CursorShape = Control.CURSOR_ARROW


func _init(new_tool_id: StringName = StringName(), new_display_name: String = "", new_cursor_shape: Control.CursorShape = Control.CURSOR_ARROW) -> void:
	tool_id = new_tool_id
	display_name = new_display_name
	cursor_shape = new_cursor_shape


func activate() -> void:
	pass


func deactivate() -> void:
	pass


func handle_event(_event: InputEvent, _world_position: Vector2) -> bool:
	return false
