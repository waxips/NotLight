# SPDX-License-Identifier: GPL-3.0-or-later
class_name HubSectionNav
extends Control

signal section_selected(section: int)

const SECTION_BOARDS: int = 0
const SECTION_LIBRARY: int = 1
const SECTION_MODULES: int = 2
const NAV_SIZE: Vector2 = Vector2(336.0, 108.0)
const BUTTON_SIZE: Vector2 = Vector2(120.0, 40.0)
const BOTTOM_ROW_Y: float = 68.0
const CONNECTOR_GAP: float = 7.0

var _boards_button: Button
var _library_button: Button
var _modules_button: Button
var _group: ButtonGroup


func _ready() -> void:
	custom_minimum_size = NAV_SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS
	_group = ButtonGroup.new()
	_boards_button = _make_button("hub.boards", SECTION_BOARDS)
	_library_button = _make_button("hub.library", SECTION_LIBRARY)
	_modules_button = _make_button("hub.modules", SECTION_MODULES)
	resized.connect(_layout_buttons)
	_layout_buttons()


func set_section(section: int) -> void:
	if _boards_button == null:
		return
	_boards_button.button_pressed = section == SECTION_BOARDS
	_library_button.button_pressed = section == SECTION_LIBRARY
	_modules_button.button_pressed = section == SECTION_MODULES
	queue_redraw()


func _make_button(localization_key: String, section: int) -> Button:
	var button: Button = Button.new()
	NotLightL10n.bind_text(button, localization_key)
	button.toggle_mode = true
	button.button_group = _group
	button.theme_type_variation = "HubNavButton"
	button.custom_minimum_size = BUTTON_SIZE
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(func() -> void: section_selected.emit(section))
	add_child(button)
	return button


func _layout_buttons() -> void:
	if _boards_button == null:
		return
	var center_x: float = size.x * 0.5
	_boards_button.position = Vector2(center_x - BUTTON_SIZE.x * 0.5, 0.0)
	_boards_button.size = BUTTON_SIZE
	_library_button.position = Vector2(0.0, BOTTOM_ROW_Y)
	_library_button.size = BUTTON_SIZE
	_modules_button.position = Vector2(size.x - BUTTON_SIZE.x, BOTTOM_ROW_Y)
	_modules_button.size = BUTTON_SIZE
	queue_redraw()


func _draw() -> void:
	if _boards_button == null:
		return
	var accent: Color = NotLightTheme.semantic_color("accent")
	var line_color: Color = Color(accent.r, accent.g, accent.b, 0.26)
	var node_color: Color = Color(accent.r, accent.g, accent.b, 0.46)
	var top_rect: Rect2 = Rect2(_boards_button.position, _boards_button.size)
	var left_rect: Rect2 = Rect2(_library_button.position, _library_button.size)
	var right_rect: Rect2 = Rect2(_modules_button.position, _modules_button.size)
	var top_bottom: Vector2 = Vector2(top_rect.get_center().x, top_rect.end.y + CONNECTOR_GAP)
	var left_top: Vector2 = Vector2(left_rect.get_center().x, left_rect.position.y - CONNECTOR_GAP)
	var right_top: Vector2 = Vector2(right_rect.get_center().x, right_rect.position.y - CONNECTOR_GAP)
	var left_side: Vector2 = Vector2(left_rect.end.x + CONNECTOR_GAP, left_rect.get_center().y)
	var right_side: Vector2 = Vector2(right_rect.position.x - CONNECTOR_GAP, right_rect.get_center().y)
	# Connect only the empty space between the three opaque navigation chips. This
	# keeps the playful graph metaphor without ever drawing through localized text.
	draw_line(top_bottom, left_top, line_color, 1.6, true)
	draw_line(top_bottom, right_top, line_color, 1.6, true)
	draw_line(left_side, right_side, Color(line_color.r, line_color.g, line_color.b, line_color.a * 0.78), 1.3, true)
	var connector_nodes: Array[Vector2] = [top_bottom, left_top, right_top]
	for point: Vector2 in connector_nodes:
		draw_circle(point, 2.4, node_color, true)
