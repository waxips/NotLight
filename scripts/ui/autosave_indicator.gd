# SPDX-License-Identifier: GPL-3.0-or-later
class_name AutosaveIndicator
extends PanelContainer

var _dot: Label


func _ready() -> void:
	theme_type_variation = "SaveStatusDot"
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(34.0, 34.0)
	_dot = Label.new()
	_dot.text = "●"
	_dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dot.add_theme_font_size_override("font_size", 12)
	add_child(_dot)
	set_state(BoardSession.SaveState.SAVED, NotLightL10n.text("library.inspector.saved"))


func set_state(state: BoardSession.SaveState, message: String) -> void:
	if _dot == null:
		return
	tooltip_text = message if not message.is_empty() else NotLightL10n.text("library.inspector.saved")
	match state:
		BoardSession.SaveState.SAVED:
			_dot.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
		BoardSession.SaveState.DIRTY:
			_dot.add_theme_color_override("font_color", NotLightTheme.semantic_color("warning"))
		BoardSession.SaveState.SAVING:
			_dot.add_theme_color_override("font_color", Color("#5483a2"))
		BoardSession.SaveState.ERROR:
			_dot.add_theme_color_override("font_color", NotLightTheme.semantic_color("danger"))
		_:
			_dot.add_theme_color_override("font_color", NotLightTheme.semantic_color("text_muted"))
