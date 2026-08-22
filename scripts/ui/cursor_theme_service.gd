# SPDX-License-Identifier: GPL-3.0-or-later
class_name CursorThemeService
extends RefCounted

const CURSOR_ROOT: String = "res://assets/cursors"


static func install() -> void:
	_install("arrow.svg", Input.CURSOR_ARROW, Vector2(2.0, 2.0))
	_install("hand.svg", Input.CURSOR_DRAG, Vector2(15.0, 15.0))
	_install("draw.svg", Input.CURSOR_CROSS, Vector2(8.0, 24.0))
	_install("text.svg", Input.CURSOR_VSPLIT, Vector2(4.0, 4.0))
	_install("formula.svg", Input.CURSOR_HELP, Vector2(4.0, 4.0))


static func _install(file_name: String, shape: Input.CursorShape, hotspot: Vector2) -> void:
	var texture: Texture2D = load(CURSOR_ROOT.path_join(file_name)) as Texture2D
	if texture != null:
		Input.set_custom_mouse_cursor(texture, shape, hotspot)
