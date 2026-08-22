# SPDX-License-Identifier: GPL-3.0-or-later
class_name ConnectorContextToolbar
extends PanelContainer

signal color_picker_requested(anchor_rect: Rect2, current_color: Color)
signal direction_requested(direction: int)
signal delete_requested

const VIEWPORT_MARGIN: float = 18.0
const TOP_UI_SAFE_Y: float = 92.0
const ANCHOR_GAP: float = 14.0
const CONNECTOR_PALETTE_PRESETS: Array[Dictionary] = [
	{"name_key": "formula.color.green", "color": Color("#2f8f5b")},
	{"name_key": "formula.color.graphite", "color": Color("#344039")},
	{"name_key": "formula.color.blue", "color": Color("#3568c8")},
	{"name_key": "formula.color.purple", "color": Color("#7656c9")},
	{"name_key": "formula.color.red", "color": Color("#b94a48")},
	{"name_key": "runtime.ui.connector_context_toolbar.6494ce14e1", "color": Color("#b7662d")},
]

var _has_context: bool = false
var _anchor_should_show: bool = false
var _anchor_rect: Rect2 = Rect2()
var _viewport_size: Vector2 = Vector2.ZERO
var _direction_buttons: Dictionary = {}
var _color_button: Button
var _current_color: Color = ConnectorStore.DEFAULT_COLOR
var _updating: bool = false


static func palette() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for preset: Dictionary in CONNECTOR_PALETTE_PRESETS:
		result.append({
			"name": NotLightL10n.text(str(preset.get("name_key", ""))),
			"color": preset.get("color", ConnectorStore.DEFAULT_COLOR),
		})
	return result


func _ready() -> void:
	theme_type_variation = "FloatingPanel"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 161
	_build_ui()


func update_context(runtime: BoardRuntime, selected_ids: PackedInt64Array) -> void:
	_has_context = false
	if runtime == null or selected_ids.size() != 1:
		_apply_visibility()
		return
	var connector_id: int = int(selected_ids[0])
	if not runtime.model.connectors.contains(connector_id):
		_apply_visibility()
		return
	_has_context = true
	_updating = true
	_current_color = runtime.model.connectors.get_color(connector_id)
	_update_color_button(_current_color)
	var direction: int = runtime.model.connectors.get_direction(connector_id)
	for key: Variant in _direction_buttons.keys():
		var button: Button = _direction_buttons[key] as Button
		button.set_pressed_no_signal(int(key) == direction)
	_updating = false
	_apply_visibility()


func set_toolbar_anchor(screen_rect: Rect2, viewport_size: Vector2, should_show: bool) -> void:
	_anchor_rect = screen_rect
	_viewport_size = viewport_size
	_anchor_should_show = should_show
	_apply_visibility()


func apply_color_from_popover(color: Color) -> void:
	_current_color = color
	_update_color_button(color)


func _apply_visibility() -> void:
	visible = _has_context and _anchor_should_show and _anchor_rect.has_area()
	if visible:
		call_deferred("_place_near_anchor")


func _place_near_anchor() -> void:
	if not visible:
		return
	var desired_size: Vector2 = get_combined_minimum_size()
	size = desired_size
	var x: float = _anchor_rect.get_center().x - desired_size.x * 0.5
	x = clampf(x, VIEWPORT_MARGIN, maxf(VIEWPORT_MARGIN, _viewport_size.x - desired_size.x - VIEWPORT_MARGIN))
	var y: float = _anchor_rect.position.y - desired_size.y - ANCHOR_GAP
	if y < TOP_UI_SAFE_Y:
		y = _anchor_rect.end.y + ANCHOR_GAP
	y = clampf(y, TOP_UI_SAFE_Y, maxf(TOP_UI_SAFE_Y, _viewport_size.y - desired_size.y - VIEWPORT_MARGIN))
	position = Vector2(x, y)


func _build_ui() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	add_child(row)

	var label: Label = Label.new()
	label.text = "↝"
	NotLightL10n.bind_tooltip(label, "runtime.ui.connector_context_toolbar.78fc844e34")
	label.theme_type_variation = "TitleLabel"
	label.custom_minimum_size = Vector2(36.0, 40.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	row.add_child(_separator())

	var direction_group: ButtonGroup = ButtonGroup.new()
	_add_direction_button(row, ConnectorStore.DIRECTION_NONE, NotLightL10n.text("performance.unavailable"), "runtime.ui.connector_context_toolbar.44dd6e6dcf", direction_group)
	_add_direction_button(row, ConnectorStore.DIRECTION_FORWARD, "→", "runtime.ui.connector_context_toolbar.223d1d72ac", direction_group)
	_add_direction_button(row, ConnectorStore.DIRECTION_REVERSE, "←", "runtime.ui.connector_context_toolbar.90a5ac0f9f", direction_group)
	_add_direction_button(row, ConnectorStore.DIRECTION_BOTH, "↔", "runtime.ui.connector_context_toolbar.e0be6b9a42", direction_group)
	row.add_child(_separator())

	_color_button = Button.new()
	_color_button.text = "●"
	NotLightL10n.bind_tooltip(_color_button, "runtime.ui.board_screen.8a534f90e4")
	_prepare_button(_color_button, "IconButton", Vector2(42.0, 40.0))
	_color_button.pressed.connect(func() -> void:
		color_picker_requested.emit(_color_button.get_global_rect(), _current_color)
	)
	row.add_child(_color_button)
	row.add_child(_separator())

	var delete_button: Button = Button.new()
	delete_button.icon = load("res://assets/icons/trash.svg") as Texture2D
	NotLightL10n.bind_tooltip(delete_button, "runtime.ui.connector_context_toolbar.c2e580ae70")
	_prepare_button(delete_button, "DangerIconButton", Vector2(40.0, 40.0))
	delete_button.pressed.connect(func() -> void: delete_requested.emit())
	row.add_child(delete_button)


func _add_direction_button(
	row: HBoxContainer,
	direction: int,
	label: String,
	tooltip_key: String,
	group: ButtonGroup
) -> void:
	var button: Button = Button.new()
	button.text = label
	NotLightL10n.bind_tooltip(button, tooltip_key)
	button.toggle_mode = true
	button.button_group = group
	_prepare_button(button, "IconButton", Vector2(42.0, 40.0))
	button.toggled.connect(func(enabled: bool) -> void:
		if enabled and not _updating:
			direction_requested.emit(direction)
	)
	_direction_buttons[direction] = button
	row.add_child(button)


func _prepare_button(button: BaseButton, variation: String, minimum_size: Vector2) -> void:
	button.theme_type_variation = variation
	button.custom_minimum_size = minimum_size
	button.focus_mode = Control.FOCUS_NONE


func _update_color_button(color: Color) -> void:
	if _color_button == null:
		return
	_color_button.tooltip_text = NotLightL10n.text("runtime.ui.connector_context_toolbar.7c8bb57862") % color.to_html(false).to_upper()
	_color_button.add_theme_color_override("font_color", color)
	_color_button.add_theme_color_override("font_hover_color", color)
	_color_button.add_theme_color_override("font_pressed_color", color)


func _separator() -> VSeparator:
	var separator: VSeparator = VSeparator.new()
	separator.custom_minimum_size = Vector2(4.0, 30.0)
	return separator
