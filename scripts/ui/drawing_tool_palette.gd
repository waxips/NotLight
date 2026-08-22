# SPDX-License-Identifier: GPL-3.0-or-later
class_name DrawingToolPalette
extends PanelContainer

signal brush_changed(style_id: int, color: Color, width: float, spray_spread: float, eraser_enabled: bool, eraser_radius: float)
signal color_picker_requested(anchor_rect: Rect2, current_color: Color)

const QUICK_COLORS: Array[Color] = [
	Color("#245cff"), Color("#24885a"), Color("#ee5965"), Color("#202421"),
	Color("#f1b83f"), Color("#8c63dc"), Color("#21a7b5"), Color("#f7f3e9"),
]
const QUICK_COLOR_PRESET_DEFS: Array[Dictionary] = [
	{"name_key": "formula.color.blue", "color": Color("#245cff")},
	{"name_key": "formula.color.green", "color": Color("#24885a")},
	{"name_key": "formula.color.red", "color": Color("#ee5965")},
	{"name_key": "formula.color.graphite", "color": Color("#202421")},
	{"name_key": "runtime.ui.drawing_tool_palette.a93b622d2c", "color": Color("#f1b83f")},
	{"name_key": "formula.color.purple", "color": Color("#8c63dc")},
	{"name_key": "formula.color.teal", "color": Color("#21a7b5")},
	{"name_key": "runtime.ui.drawing_tool_palette.1846be9972", "color": Color("#f7f3e9")},
]
const PANEL_MIN_WIDTH: float = 316.0
const PANEL_HARD_MIN_WIDTH: float = 248.0
const PANEL_MAX_WIDTH: float = 388.0
const PANEL_MAX_HEIGHT: float = 620.0
const VIEWPORT_MARGIN: float = 18.0
const ERASER_MIN: float = 6.0
const ERASER_MAX: float = 56.0

var settings: AppSettingsStore
var _scroll: ScrollContainer
var _content: VBoxContainer
var _tool_buttons: Dictionary = {}
var _tool_group: ButtonGroup
var _width_slider: HSlider
var _width_label: Label
var _spread_row: HBoxContainer
var _spread_slider: HSlider
var _spread_label: Label
var _color_controls: VBoxContainer
var _color_button: Button
var _preset_option: OptionButton
var _preset_name: LineEdit
var _save_button: Button
var _delete_button: Button
var _style_id: int = StrokeStore.STYLE_PEN
var _eraser_enabled: bool = false
var _color: Color = Color("#245cff")
var _width: float = 4.0
var _spray_spread: float = 1.0
var _eraser_radius: float = 18.0
var _preset_ids: Array[String] = []
var _guard: bool = false


static func quick_color_presets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for preset: Dictionary in QUICK_COLOR_PRESET_DEFS:
		result.append({
			"name": NotLightL10n.text(str(preset.get("name_key", ""))),
			"color": preset.get("color", Color.WHITE),
		})
	return result


func _ready() -> void:
	theme_type_variation = "DrawingPalettePanel"
	z_index = 360
	visible = false
	clip_contents = false
	custom_minimum_size = Vector2(PANEL_HARD_MIN_WIDTH, 0.0)
	_build_ui()


func configure(settings_store: AppSettingsStore) -> void:
	settings = settings_store
	if settings != null:
		if not settings.settings_changed.is_connected(_on_settings_changed):
			settings.settings_changed.connect(_on_settings_changed)
		_apply_settings_snapshot(settings.get_drawing_brush_snapshot())
	_rebuild_presets()


func set_tool_active(active: bool, viewport_size: Vector2, tool_rail_rect: Rect2) -> void:
	visible = active
	if active:
		update_layout(viewport_size, tool_rail_rect)


func update_layout(viewport_size: Vector2, tool_rail_rect: Rect2) -> void:
	if not visible:
		return
	var available_width: float = maxf(PANEL_HARD_MIN_WIDTH, viewport_size.x - VIEWPORT_MARGIN * 2.0)
	var desired_width: float = clampf(PANEL_MIN_WIDTH, PANEL_HARD_MIN_WIDTH, minf(PANEL_MAX_WIDTH, available_width))
	var x: float = tool_rail_rect.end.x + 12.0
	if x + desired_width > viewport_size.x - VIEWPORT_MARGIN:
		x = maxf(VIEWPORT_MARGIN, tool_rail_rect.position.x - desired_width - 12.0)
	var y: float = clampf(tool_rail_rect.position.y, VIEWPORT_MARGIN, maxf(VIEWPORT_MARGIN, viewport_size.y - 260.0))
	var available_height: float = maxf(220.0, viewport_size.y - y - VIEWPORT_MARGIN)
	var content_height: float = _content.get_combined_minimum_size().y + 24.0 if _content != null else 360.0
	var desired_height: float = minf(minf(PANEL_MAX_HEIGHT, available_height), maxf(300.0, content_height))
	position = Vector2(x, y)
	size = Vector2(desired_width, desired_height)
	if _scroll != null:
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO


func apply_external_color(color: Color) -> void:
	_color = color
	_refresh_color_button()
	_commit_brush()


func _build_ui() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 9)
	_scroll.add_child(_content)

	var title: Label = Label.new()
	NotLightL10n.bind_text(title, "drawing.title")
	title.theme_type_variation = "SectionTitleLabel"
	_content.add_child(title)
	var help: Label = Label.new()
	NotLightL10n.bind_text(help, "drawing.help")
	help.theme_type_variation = "CaptionLabel"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(help)

	_build_tool_selector()
	_content.add_child(HSeparator.new())
	_build_width_controls()
	_build_color_controls()
	_content.add_child(HSeparator.new())
	_build_preset_controls()
	_refresh_controls()


func _build_tool_selector() -> void:
	_tool_group = ButtonGroup.new()
	_tool_group.allow_unpress = false
	var flow: HFlowContainer = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	_content.add_child(flow)
	_add_tool_button(flow, StrokeStore.STYLE_PEN, NotLightL10n.text("drawing.style.pen"))
	_add_tool_button(flow, StrokeStore.STYLE_HIGHLIGHTER, NotLightL10n.text("drawing.style.highlighter"))
	_add_tool_button(flow, StrokeStore.STYLE_PENCIL, NotLightL10n.text("drawing.style.pencil"))
	_add_tool_button(flow, StrokeStore.STYLE_SPRAY, NotLightL10n.text("drawing.style.spray"))
	var eraser: Button = Button.new()
	NotLightL10n.bind_text(eraser, "drawing.eraser")
	eraser.toggle_mode = true
	eraser.button_group = _tool_group
	eraser.theme_type_variation = "SecondaryButton"
	eraser.pressed.connect(_select_eraser)
	flow.add_child(eraser)
	_tool_buttons["eraser"] = eraser


func _add_tool_button(parent: Control, style_id: int, title: String) -> void:
	var button: Button = Button.new()
	button.text = title
	button.toggle_mode = true
	button.button_group = _tool_group
	button.theme_type_variation = "SecondaryButton"
	button.pressed.connect(_select_style.bind(style_id))
	parent.add_child(button)
	_tool_buttons[style_id] = button


func _build_width_controls() -> void:
	var width_row: HBoxContainer = HBoxContainer.new()
	width_row.add_theme_constant_override("separation", 8)
	_content.add_child(width_row)
	var caption: Label = Label.new()
	NotLightL10n.bind_text(caption, "drawing.width")
	caption.custom_minimum_size = Vector2(78.0, 0.0)
	caption.theme_type_variation = "CaptionStrongLabel"
	width_row.add_child(caption)
	_width_slider = HSlider.new()
	_width_slider.scrollable = false
	_width_slider.min_value = 1.0
	_width_slider.max_value = 18.0
	_width_slider.step = 0.5
	_width_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_width_slider.value_changed.connect(_on_width_changed)
	width_row.add_child(_width_slider)
	_width_label = Label.new()
	_width_label.custom_minimum_size = Vector2(52.0, 0.0)
	_width_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	width_row.add_child(_width_label)

	_spread_row = HBoxContainer.new()
	_spread_row.add_theme_constant_override("separation", 8)
	_content.add_child(_spread_row)
	var spread_caption: Label = Label.new()
	NotLightL10n.bind_text(spread_caption, "drawing.spray.spread")
	spread_caption.custom_minimum_size = Vector2(78.0, 0.0)
	spread_caption.theme_type_variation = "CaptionStrongLabel"
	_spread_row.add_child(spread_caption)
	_spread_slider = HSlider.new()
	_spread_slider.scrollable = false
	_spread_slider.min_value = StrokeStore.MIN_SPRAY_SPREAD
	_spread_slider.max_value = StrokeStore.MAX_SPRAY_SPREAD
	_spread_slider.step = 0.05
	_spread_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spread_slider.value_changed.connect(_on_spread_changed)
	_spread_row.add_child(_spread_slider)
	_spread_label = Label.new()
	_spread_label.custom_minimum_size = Vector2(52.0, 0.0)
	_spread_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_spread_row.add_child(_spread_label)


func _build_color_controls() -> void:
	_color_controls = VBoxContainer.new()
	_color_controls.add_theme_constant_override("separation", 6)
	_content.add_child(_color_controls)
	var caption: Label = Label.new()
	NotLightL10n.bind_text(caption, "drawing.color_label")
	caption.theme_type_variation = "CaptionStrongLabel"
	_color_controls.add_child(caption)
	var flow: HFlowContainer = HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	_color_controls.add_child(flow)
	for swatch_color: Color in QUICK_COLORS:
		var swatch: Button = Button.new()
		swatch.custom_minimum_size = Vector2(28.0, 28.0)
		swatch.tooltip_text = swatch_color.to_html(false).to_upper()
		_apply_swatch_style(swatch, swatch_color)
		swatch.pressed.connect(_select_quick_color.bind(swatch_color))
		flow.add_child(swatch)
	_color_button = Button.new()
	_color_button.theme_type_variation = "GhostButton"
	_color_button.pressed.connect(_request_color_picker)
	_color_controls.add_child(_color_button)


func _build_preset_controls() -> void:
	var preset_label: Label = Label.new()
	NotLightL10n.bind_text(preset_label, "drawing.presets")
	preset_label.theme_type_variation = "CaptionStrongLabel"
	_content.add_child(preset_label)
	_preset_option = OptionButton.new()
	_preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_option.item_selected.connect(_on_preset_selected)
	_content.add_child(_preset_option)
	var save_row: HBoxContainer = HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 6)
	_content.add_child(save_row)
	_preset_name = LineEdit.new()
	NotLightL10n.bind_placeholder_text(_preset_name, "drawing.preset.name_placeholder")
	_preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_preset_name)
	_save_button = Button.new()
	NotLightL10n.bind_text(_save_button, "drawing.preset.save")
	_save_button.theme_type_variation = "SecondaryButton"
	_save_button.pressed.connect(_save_user_preset)
	save_row.add_child(_save_button)
	_delete_button = Button.new()
	NotLightL10n.bind_text(_delete_button, "drawing.preset.delete")
	_delete_button.theme_type_variation = "GhostDangerButton"
	_delete_button.pressed.connect(_delete_user_preset)
	_content.add_child(_delete_button)


func _select_style(style_id: int) -> void:
	if _guard:
		return
	_eraser_enabled = false
	_style_id = clampi(style_id, StrokeStore.STYLE_PEN, StrokeStore.STYLE_SPRAY)
	_width = minf(_width, StrokeStore.editor_max_width_for_style(_style_id))
	_refresh_controls()
	_commit_brush()


func _select_eraser() -> void:
	if _guard:
		return
	_eraser_enabled = true
	_refresh_controls()
	_emit_brush()


func _on_width_changed(value: float) -> void:
	if _guard:
		return
	if _eraser_enabled:
		_eraser_radius = clampf(value, ERASER_MIN, ERASER_MAX)
		if settings != null:
			settings.set_drawing_eraser_radius(_eraser_radius)
	else:
		_width = clampf(value, StrokeStore.MIN_WIDTH, StrokeStore.editor_max_width_for_style(_style_id))
		_commit_brush()
	_refresh_labels()


func _on_spread_changed(value: float) -> void:
	if _guard:
		return
	_spray_spread = clampf(value, StrokeStore.MIN_SPRAY_SPREAD, StrokeStore.MAX_SPRAY_SPREAD)
	_commit_brush()
	_refresh_labels()


func _select_quick_color(value: Color) -> void:
	_color = value
	_refresh_color_button()
	_commit_brush()


func _request_color_picker() -> void:
	color_picker_requested.emit(_color_button.get_global_rect(), _color)


func _commit_brush() -> void:
	if settings != null:
		settings.set_drawing_brush(_style_id, _color, _width, _spray_spread)
	_emit_brush()


func _emit_brush() -> void:
	brush_changed.emit(_style_id, _color, _width, _spray_spread, _eraser_enabled, _eraser_radius)


func _apply_settings_snapshot(snapshot: Dictionary) -> void:
	_guard = true
	_style_id = clampi(int(snapshot.get("style", StrokeStore.STYLE_PEN)), StrokeStore.STYLE_PEN, StrokeStore.STYLE_SPRAY)
	var raw_color: Variant = snapshot.get("color", Color("#245cff"))
	_color = raw_color as Color if raw_color is Color else Color.from_string(str(raw_color), Color("#245cff"))
	_width = clampf(float(snapshot.get("width", 4.0)), StrokeStore.MIN_WIDTH, StrokeStore.editor_max_width_for_style(_style_id))
	_spray_spread = clampf(float(snapshot.get("spray_spread", 1.0)), StrokeStore.MIN_SPRAY_SPREAD, StrokeStore.MAX_SPRAY_SPREAD)
	_eraser_radius = clampf(float(snapshot.get("eraser_radius", 18.0)), ERASER_MIN, ERASER_MAX)
	_guard = false
	_refresh_controls()
	_emit_brush()


func _refresh_controls() -> void:
	if _width_slider == null:
		return
	_guard = true
	for raw_key: Variant in _tool_buttons.keys():
		var button: Button = _tool_buttons[raw_key] as Button
		if raw_key is int:
			button.set_pressed_no_signal(not _eraser_enabled and int(raw_key) == _style_id)
		else:
			button.set_pressed_no_signal(_eraser_enabled)
	_width_slider.min_value = ERASER_MIN if _eraser_enabled else 1.0
	_width_slider.max_value = ERASER_MAX if _eraser_enabled else StrokeStore.editor_max_width_for_style(_style_id)
	_width_slider.step = 1.0 if _eraser_enabled else 0.5
	_width_slider.value = _eraser_radius if _eraser_enabled else minf(_width, _width_slider.max_value)
	_spread_slider.value = _spray_spread
	_spread_row.visible = not _eraser_enabled and _style_id == StrokeStore.STYLE_SPRAY
	_color_controls.modulate = Color(1.0, 1.0, 1.0, 0.45) if _eraser_enabled else Color.WHITE
	_color_button.disabled = _eraser_enabled
	_guard = false
	_refresh_labels()
	_refresh_color_button()
	if visible:
		call_deferred("_request_parent_relayout")


func _request_parent_relayout() -> void:
	# BoardScreen will also relayout on resize; this only refreshes ScrollContainer
	# minimum sizes immediately after the spray row appears/disappears.
	if _scroll != null:
		_scroll.queue_sort()


func _refresh_labels() -> void:
	if _width_label != null:
		_width_label.text = NotLightL10n.text("ui.format.width_px") % _width_slider.value
	if _spread_label != null:
		_spread_label.text = NotLightL10n.text("ui.format.scale_two_decimals") % _spray_spread


func _refresh_color_button() -> void:
	if _color_button != null:
		_color_button.text = NotLightL10n.text("drawing.color", {"color": _color.to_html(false).to_upper()})


func _apply_swatch_style(button: Button, value: Color) -> void:
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = value
	normal.border_color = NotLightTheme.semantic_color("border")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(14)
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.border_color = NotLightTheme.semantic_color("accent")
	hover.set_border_width_all(2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)


func _rebuild_presets() -> void:
	if _preset_option == null:
		return
	_preset_option.clear()
	_preset_ids.clear()
	_add_builtin_preset(NotLightL10n.text("drawing.preset.thin_pen"), StrokeStore.STYLE_PEN, Color("#245cff"), 3.0, 1.0)
	_add_builtin_preset(NotLightL10n.text("drawing.preset.bold_pen"), StrokeStore.STYLE_PEN, Color("#202421"), 7.0, 1.0)
	_add_builtin_preset(NotLightL10n.text("drawing.style.highlighter"), StrokeStore.STYLE_HIGHLIGHTER, Color("#f1b83f"), 9.0, 1.0)
	_add_builtin_preset(NotLightL10n.text("drawing.style.pencil"), StrokeStore.STYLE_PENCIL, Color("#454a46"), 3.5, 1.0)
	_add_builtin_preset(NotLightL10n.text("drawing.style.spray"), StrokeStore.STYLE_SPRAY, Color("#24885a"), 7.0, 1.25)
	if settings != null:
		for record: Dictionary in settings.list_user_drawing_presets():
			_preset_option.add_item(str(record.get("name", NotLightL10n.text("drawing.preset.unnamed"))))
			_preset_ids.append(str(record.get("id", "")))
	_delete_button.disabled = true


func _add_builtin_preset(name: String, style: int, color: Color, width: float, spread: float) -> void:
	_preset_option.add_item(name)
	_preset_option.set_item_metadata(_preset_option.item_count - 1, {"style": style, "color": color, "width": width, "spray_spread": spread})
	_preset_ids.append("")


func _on_preset_selected(index: int) -> void:
	if index < 0 or index >= _preset_option.item_count:
		return
	var preset_id: String = _preset_ids[index] if index < _preset_ids.size() else ""
	var record: Dictionary = {}
	if preset_id.is_empty():
		var metadata: Variant = _preset_option.get_item_metadata(index)
		if metadata is Dictionary:
			record = metadata as Dictionary
	elif settings != null:
		for candidate: Dictionary in settings.list_user_drawing_presets():
			if str(candidate.get("id", "")) == preset_id:
				record = candidate
				break
	if record.is_empty():
		return
	_style_id = clampi(int(record.get("style", StrokeStore.STYLE_PEN)), StrokeStore.STYLE_PEN, StrokeStore.STYLE_SPRAY)
	var raw_color: Variant = record.get("color", Color("#245cff"))
	_color = raw_color as Color if raw_color is Color else Color.from_string(str(raw_color), Color("#245cff"))
	_width = clampf(float(record.get("width", 4.0)), StrokeStore.MIN_WIDTH, StrokeStore.editor_max_width_for_style(_style_id))
	_spray_spread = clampf(float(record.get("spray_spread", 1.0)), StrokeStore.MIN_SPRAY_SPREAD, StrokeStore.MAX_SPRAY_SPREAD)
	_eraser_enabled = false
	_refresh_controls()
	_commit_brush()
	_delete_button.disabled = preset_id.is_empty()


func _save_user_preset() -> void:
	if settings == null:
		return
	var preset_id: String = settings.save_user_drawing_preset(_preset_name.text, _style_id, _color, _width, _spray_spread)
	if not preset_id.is_empty():
		_preset_name.clear()
		_rebuild_presets()


func _delete_user_preset() -> void:
	if settings == null or _preset_option.selected < 0 or _preset_option.selected >= _preset_ids.size():
		return
	var preset_id: String = _preset_ids[_preset_option.selected]
	if not preset_id.is_empty() and settings.delete_user_drawing_preset(preset_id):
		_rebuild_presets()


func _on_settings_changed(_snapshot: Dictionary) -> void:
	if settings != null:
		_apply_settings_snapshot(settings.get_drawing_brush_snapshot())
