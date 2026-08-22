# SPDX-License-Identifier: GPL-3.0-or-later
class_name FormulaContextToolbar
extends PanelContainer

signal edit_requested
signal copy_latex_requested
signal display_mode_requested(mode: int)
signal color_picker_requested(anchor_rect: Rect2, current_color: Color)
signal duplicate_requested
signal delete_requested

const VIEWPORT_MARGIN: float = 16.0
const TOP_UI_SAFE_Y: float = 92.0
const ANCHOR_GAP: float = 12.0
const FORMULA_PALETTE_COLORS: Array[Dictionary] = [
	{"name_key": "formula.color.graphite", "color": Color("#202a24")},
	{"name_key": "formula.color.green", "color": Color("#24885a")},
	{"name_key": "formula.color.blue", "color": Color("#3568c8")},
	{"name_key": "formula.color.red", "color": Color("#ee5965")},
	{"name_key": "formula.color.purple", "color": Color("#8c63dc")},
	{"name_key": "formula.color.teal", "color": Color("#21a7b5")},
]

var _has_context: bool = false
var _anchor_should_show: bool = false
var _anchor_rect: Rect2 = Rect2()
var _viewport_size: Vector2 = Vector2.ZERO
var _mode_option: OptionButton
var _color_button: Button
var _current_color: Color = FormulaStore.DEFAULT_FOREGROUND
var _updating: bool = false


static func palette() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for preset: Dictionary in FORMULA_PALETTE_COLORS:
		result.append({
			"name": NotLightL10n.text(str(preset.get("name_key", ""))),
			"color": preset.get("color", FormulaStore.DEFAULT_FOREGROUND),
		})
	return result


func _ready() -> void:
	theme_type_variation = "ContextToolbarPanel"
	visible = false
	z_index = 440
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func update_context(runtime: BoardRuntime, selected_ids: PackedInt64Array) -> void:
	_has_context = false
	if runtime == null or selected_ids.size() != 1:
		_apply_visibility()
		return
	var entity_id: int = int(selected_ids[0])
	if not runtime.model.formulas.contains(entity_id):
		_apply_visibility()
		return
	_has_context = true
	_updating = true
	var record: Dictionary = FormulaRenderService.normalize_record(runtime.model.formulas.get_record(entity_id))
	_select_mode(int(record.get("display_mode", FormulaStore.DEFAULT_DISPLAY_MODE)))
	var raw_color: Variant = record.get("foreground", FormulaStore.DEFAULT_FOREGROUND)
	_current_color = raw_color if raw_color is Color else FormulaStore.DEFAULT_FOREGROUND
	_update_color_button()
	_updating = false
	_apply_visibility()


func set_toolbar_anchor(screen_rect: Rect2, viewport_size: Vector2, should_show: bool) -> void:
	_anchor_rect = screen_rect
	_viewport_size = viewport_size
	_anchor_should_show = should_show
	_apply_visibility()


func apply_color_from_popover(color: Color) -> void:
	_current_color = Color(color.r, color.g, color.b, 1.0)
	_update_color_button()


func _build_ui() -> void:
	var row: HFlowContainer = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 5)
	row.add_theme_constant_override("v_separation", 5)
	add_child(row)

	var type_label: Label = Label.new()
	type_label.text = "ƒx"
	NotLightL10n.bind_tooltip(type_label, "formula.context.title")
	type_label.theme_type_variation = "CaptionStrongLabel"
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	type_label.custom_minimum_size = Vector2(38.0, 36.0)
	type_label.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
	row.add_child(type_label)

	var edit_button: Button = Button.new()
	NotLightL10n.bind_text(edit_button, "formula.context.edit")
	NotLightL10n.bind_tooltip(edit_button, "formula.context.edit_help")
	edit_button.theme_type_variation = "GhostButton"
	edit_button.custom_minimum_size = Vector2(112.0, 36.0)
	edit_button.pressed.connect(func() -> void: edit_requested.emit())
	row.add_child(edit_button)

	_mode_option = OptionButton.new()
	_mode_option.theme_type_variation = "SettingsOptionButton"
	_mode_option.custom_minimum_size = Vector2(132.0, 36.0)
	_mode_option.add_item(NotLightL10n.text("formula.mode.inline"), FormulaStore.DISPLAY_INLINE)
	_mode_option.add_item(NotLightL10n.text("formula.mode.block"), FormulaStore.DISPLAY_BLOCK)
	_mode_option.item_selected.connect(_on_mode_selected)
	row.add_child(_mode_option)

	_color_button = Button.new()
	_color_button.custom_minimum_size = Vector2(76.0, 36.0)
	NotLightL10n.bind_tooltip(_color_button, "formula.editor.color")
	_color_button.focus_mode = Control.FOCUS_NONE
	_color_button.pressed.connect(func() -> void:
		color_picker_requested.emit(_color_button.get_global_rect(), _current_color)
	)
	row.add_child(_color_button)
	_update_color_button()

	var copy_button: Button = Button.new()
	NotLightL10n.bind_text(copy_button, "formula.context.copy")
	NotLightL10n.bind_tooltip(copy_button, "formula.context.copy_help")
	copy_button.theme_type_variation = "GhostButton"
	copy_button.pressed.connect(func() -> void: copy_latex_requested.emit())
	row.add_child(copy_button)

	var duplicate_button: Button = Button.new()
	NotLightL10n.bind_text(duplicate_button, "formula.context.duplicate")
	NotLightL10n.bind_tooltip(duplicate_button, "formula.context.duplicate_help")
	duplicate_button.theme_type_variation = "GhostButton"
	duplicate_button.pressed.connect(func() -> void: duplicate_requested.emit())
	row.add_child(duplicate_button)

	var delete_button: Button = Button.new()
	delete_button.icon = load("res://assets/icons/trash.svg") as Texture2D
	NotLightL10n.bind_tooltip(delete_button, "formula.context.delete_help")
	delete_button.theme_type_variation = "GhostDangerButton"
	delete_button.custom_minimum_size = Vector2(40.0, 36.0)
	delete_button.pressed.connect(func() -> void: delete_requested.emit())
	row.add_child(delete_button)


func _on_mode_selected(_index: int) -> void:
	if not _updating:
		display_mode_requested.emit(_mode_option.get_selected_id())


func _select_mode(mode: int) -> void:
	for index: int in range(_mode_option.item_count):
		if _mode_option.get_item_id(index) == mode:
			_mode_option.select(index)
			return


func _update_color_button() -> void:
	if _color_button == null:
		return
	_color_button.text = NotLightL10n.text("ui.format.hex_color") % _current_color.to_html(false).to_upper()
	var normal: StyleBoxFlat = _swatch_style(_current_color, NotLightTheme.semantic_color("border_strong"))
	var hover: StyleBoxFlat = _swatch_style(_current_color.lightened(0.06), NotLightTheme.semantic_color("accent"))
	var pressed: StyleBoxFlat = _swatch_style(_current_color.darkened(0.04), NotLightTheme.semantic_color("accent"))
	_color_button.add_theme_stylebox_override("normal", normal)
	_color_button.add_theme_stylebox_override("hover", hover)
	_color_button.add_theme_stylebox_override("pressed", pressed)
	_color_button.add_theme_stylebox_override("hover_pressed", pressed)
	var luminance: float = 0.2126 * _current_color.r + 0.7152 * _current_color.g + 0.0722 * _current_color.b
	var text_color: Color = Color("#172019") if luminance > 0.58 else Color("#fffdf7")
	_color_button.add_theme_color_override("font_color", text_color)
	_color_button.add_theme_color_override("font_hover_color", text_color)
	_color_button.add_theme_color_override("font_pressed_color", text_color)


func _swatch_style(color: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	return style


func _apply_visibility() -> void:
	visible = _has_context and _anchor_should_show and _anchor_rect.has_area()
	if visible:
		call_deferred("_place_near_anchor")


func _place_near_anchor() -> void:
	if not visible:
		return
	var desired: Vector2 = get_combined_minimum_size()
	desired.x = minf(desired.x, maxf(300.0, _viewport_size.x - VIEWPORT_MARGIN * 2.0))
	var x: float = clampf(
		_anchor_rect.get_center().x - desired.x * 0.5,
		VIEWPORT_MARGIN,
		maxf(VIEWPORT_MARGIN, _viewport_size.x - desired.x - VIEWPORT_MARGIN)
	)
	var y: float = _anchor_rect.position.y - desired.y - ANCHOR_GAP
	if y < TOP_UI_SAFE_Y:
		y = _anchor_rect.end.y + ANCHOR_GAP
	y = clampf(y, TOP_UI_SAFE_Y, maxf(TOP_UI_SAFE_Y, _viewport_size.y - desired.y - VIEWPORT_MARGIN))
	position = Vector2(x, y)
	size = desired
