# SPDX-License-Identifier: GPL-3.0-or-later
class_name StrokeContextToolbar
extends PanelContainer

signal width_requested(width: float)
signal spray_spread_requested(spread: float)
signal color_picker_requested(anchor_rect: Rect2, current_color: Color)
signal duplicate_requested
signal delete_requested

var _style_label: Label
var _width_slider: HSlider
var _width_label: Label
var _spread_row: HBoxContainer
var _spread_slider: HSlider
var _spread_label: Label
var _color_button: Button
var _current_color: Color = Color("#245cff")
var _current_style: int = StrokeStore.STYLE_PEN
var _anchor_should_show: bool = false
var _guard: bool = false


func _ready() -> void:
	theme_type_variation = "ContextToolbarPanel"
	z_index = 440
	visible = false
	_build_ui()


func update_context(runtime: BoardRuntime, selected_ids: PackedInt64Array) -> void:
	_anchor_should_show = false
	if runtime == null or selected_ids.size() != 1:
		visible = false
		return
	var entity_id: int = int(selected_ids[0])
	if not runtime.model.strokes.contains(entity_id):
		visible = false
		return
	_anchor_should_show = true
	_guard = true
	_current_style = runtime.model.strokes.get_style_id(entity_id)
	_style_label.text = _style_name(_current_style)
	var bounds: Rect2 = runtime.model.get_entity_bounds(entity_id)
	var width: float = runtime.model.strokes.get_effective_width(entity_id, bounds)
	_width_slider.min_value = StrokeStore.MIN_WIDTH
	_width_slider.max_value = StrokeStore.editor_max_width_for_style(_current_style)
	var editor_width: float = minf(width, _width_slider.max_value)
	_width_slider.value = editor_width
	_width_label.text = NotLightL10n.text("ui.format.width_px") % editor_width
	var spread: float = runtime.model.strokes.get_spray_spread(entity_id)
	_spread_slider.value = spread
	_spread_label.text = NotLightL10n.text("ui.format.stroke_spread") % spread
	_spread_row.visible = _current_style == StrokeStore.STYLE_SPRAY
	_current_color = runtime.model.strokes.get_color(entity_id)
	_color_button.text = NotLightL10n.text("ui.format.hex_color") % _current_color.to_html(false).to_upper()
	_guard = false


func set_toolbar_anchor(anchor_rect: Rect2, viewport_size: Vector2, should_show: bool) -> void:
	var show_toolbar: bool = _anchor_should_show and should_show
	visible = show_toolbar
	if not show_toolbar:
		return
	var desired: Vector2 = get_combined_minimum_size()
	desired.x = minf(desired.x, maxf(286.0, viewport_size.x - 28.0))
	var x: float = clampf(anchor_rect.get_center().x - desired.x * 0.5, 14.0, maxf(14.0, viewport_size.x - desired.x - 14.0))
	var y: float = anchor_rect.position.y - desired.y - 10.0
	if y < 14.0:
		y = anchor_rect.end.y + 10.0
	y = clampf(y, 14.0, maxf(14.0, viewport_size.y - desired.y - 14.0))
	position = Vector2(x, y)
	size = desired


func apply_color(color: Color) -> void:
	_current_color = color
	_color_button.text = NotLightL10n.text("ui.format.hex_color") % color.to_html(false).to_upper()


func _build_ui() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var row: HFlowContainer = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	root.add_child(row)

	_style_label = Label.new()
	_style_label.theme_type_variation = "CaptionStrongLabel"
	_style_label.custom_minimum_size = Vector2(78.0, 34.0)
	_style_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_style_label)

	_width_slider = HSlider.new()
	_width_slider.scrollable = false
	_width_slider.min_value = StrokeStore.MIN_WIDTH
	_width_slider.max_value = 18.0
	_width_slider.step = 0.5
	_width_slider.custom_minimum_size = Vector2(116.0, 34.0)
	_width_slider.value_changed.connect(func(value: float) -> void:
		_width_label.text = NotLightL10n.text("ui.format.width_px") % value
		if not _guard:
			width_requested.emit(value)
	)
	row.add_child(_width_slider)
	_width_label = Label.new()
	_width_label.custom_minimum_size = Vector2(56.0, 34.0)
	_width_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_width_label)

	_color_button = Button.new()
	_color_button.theme_type_variation = "SecondaryButton"
	_color_button.custom_minimum_size = Vector2(92.0, 34.0)
	_color_button.pressed.connect(func() -> void:
		color_picker_requested.emit(_color_button.get_global_rect(), _current_color)
	)
	row.add_child(_color_button)

	var duplicate_button: Button = Button.new()
	NotLightL10n.bind_text(duplicate_button, "stroke.context.duplicate")
	duplicate_button.theme_type_variation = "GhostButton"
	duplicate_button.pressed.connect(func() -> void: duplicate_requested.emit())
	row.add_child(duplicate_button)
	var delete_button: Button = Button.new()
	NotLightL10n.bind_text(delete_button, "stroke.context.delete")
	delete_button.theme_type_variation = "GhostDangerButton"
	delete_button.pressed.connect(func() -> void: delete_requested.emit())
	row.add_child(delete_button)

	_spread_row = HBoxContainer.new()
	_spread_row.add_theme_constant_override("separation", 8)
	root.add_child(_spread_row)
	var spread_caption: Label = Label.new()
	NotLightL10n.bind_text(spread_caption, "drawing.spray.spread")
	spread_caption.theme_type_variation = "CaptionStrongLabel"
	spread_caption.custom_minimum_size = Vector2(78.0, 0.0)
	_spread_row.add_child(spread_caption)
	_spread_slider = HSlider.new()
	_spread_slider.scrollable = false
	_spread_slider.min_value = StrokeStore.MIN_SPRAY_SPREAD
	_spread_slider.max_value = StrokeStore.MAX_SPRAY_SPREAD
	_spread_slider.step = 0.05
	_spread_slider.custom_minimum_size = Vector2(150.0, 0.0)
	_spread_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spread_slider.value_changed.connect(func(value: float) -> void:
		_spread_label.text = NotLightL10n.text("ui.format.stroke_spread") % value
		if not _guard:
			spray_spread_requested.emit(value)
	)
	_spread_row.add_child(_spread_slider)
	_spread_label = Label.new()
	_spread_label.custom_minimum_size = Vector2(56.0, 0.0)
	_spread_row.add_child(_spread_label)


func _style_name(style_id: int) -> String:
	match style_id:
		StrokeStore.STYLE_HIGHLIGHTER:
			return NotLightL10n.text("drawing.style.highlighter")
		StrokeStore.STYLE_PENCIL:
			return NotLightL10n.text("drawing.style.pencil")
		StrokeStore.STYLE_SPRAY:
			return NotLightL10n.text("drawing.style.spray")
		_:
			return NotLightL10n.text("drawing.style.pen")
