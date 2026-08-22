# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardColorPopover
extends PanelContainer

signal color_committed(color: Color)
signal canceled

const VIEWPORT_MARGIN: float = 16.0
const ANCHOR_GAP: float = 10.0
const DEFAULT_SIZE: Vector2 = Vector2(344.0, 424.0)
const MINIMUM_USABLE_SIZE: Vector2 = Vector2(286.0, 250.0)

var _picker: ColorPicker
var _title_label: Label
var _preview_panel: PanelContainer
var _preview_style: StyleBoxFlat
var _swatch_grid: GridContainer
var _scroll: ScrollContainer
var _advanced_button: Button
var _initial_color: Color = Color.WHITE
var _viewport_size: Vector2 = Vector2.ZERO
var _anchor_rect: Rect2 = Rect2()
var _swatch_signature: String = ""


func _ready() -> void:
	theme_type_variation = "FloatingPanel"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 620
	clip_contents = true
	_build_ui()


func show_for(
	anchor_rect: Rect2,
	viewport_size: Vector2,
	current_color: Color,
	allow_alpha: bool,
	title: String,
	presets: Array[Dictionary]
) -> void:
	_anchor_rect = anchor_rect
	_viewport_size = viewport_size
	_initial_color = current_color
	_title_label.text = title
	NotLightColorPickerStyle.configure_picker(_picker, allow_alpha, false)
	_picker.color = current_color
	_set_advanced_controls(false)
	_rebuild_swatches(presets)
	_update_preview(current_color)
	# Control z_index only affects drawing in Godot 4.4. Move the popover to the
	# end of the sibling list as well so later-created panels cannot steal GUI input
	# from a visually frontmost color picker (notably FormulaEditorPanel).
	move_to_front()
	visible = true
	_place_inside_viewport()


func hide_without_commit() -> void:
	if not visible:
		return
	visible = false
	canceled.emit()


func update_viewport(viewport_size: Vector2) -> void:
	_viewport_size = viewport_size
	if visible:
		_place_inside_viewport()


func _build_ui() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)

	_title_label = Label.new()
	NotLightL10n.bind_text(_title_label, "drawing.color_label")
	_title_label.theme_type_variation = "SectionLabel"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	var close_button: Button = Button.new()
	close_button.text = "×"
	NotLightL10n.bind_tooltip(close_button, "common.close")
	close_button.theme_type_variation = "IconButton"
	close_button.custom_minimum_size = Vector2(36.0, 34.0)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(hide_without_commit)
	header.add_child(close_button)

	var divider: HSeparator = HSeparator.new()
	root.add_child(divider)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	_scroll.follow_focus = true
	_scroll.custom_minimum_size = Vector2(0.0, 150.0)
	root.add_child(_scroll)

	var body: VBoxContainer = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	_scroll.add_child(body)

	var palette_label: Label = Label.new()
	NotLightL10n.bind_text(palette_label, "color_picker.quick_colors")
	palette_label.theme_type_variation = "CaptionStrongLabel"
	body.add_child(palette_label)

	_swatch_grid = GridContainer.new()
	_swatch_grid.columns = 8
	_swatch_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_swatch_grid.add_theme_constant_override("h_separation", 6)
	_swatch_grid.add_theme_constant_override("v_separation", 6)
	body.add_child(_swatch_grid)

	_picker = ColorPicker.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	NotLightColorPickerStyle.configure_picker(_picker, false, false)
	_picker.color_changed.connect(_update_preview)
	body.add_child(_picker)

	_advanced_button = Button.new()
	NotLightL10n.bind_text(_advanced_button, "color_picker.show_values")
	NotLightL10n.bind_tooltip(_advanced_button, "color_picker.values_help")
	_advanced_button.theme_type_variation = "GhostButton"
	_advanced_button.toggle_mode = true
	_advanced_button.pressed.connect(_toggle_advanced_controls)
	body.add_child(_advanced_button)

	var footer_divider: HSeparator = HSeparator.new()
	root.add_child(footer_divider)

	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	root.add_child(footer)

	_preview_panel = PanelContainer.new()
	_preview_panel.custom_minimum_size = Vector2(44.0, 34.0)
	NotLightL10n.bind_tooltip(_preview_panel, "color_picker.current")
	_preview_style = _swatch_style(Color.WHITE, NotLightTheme.semantic_color("border_strong"))
	_preview_panel.add_theme_stylebox_override("panel", _preview_style)
	footer.add_child(_preview_panel)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	var cancel_button: Button = Button.new()
	NotLightL10n.bind_text(cancel_button, "common.cancel")
	cancel_button.theme_type_variation = "GhostButton"
	cancel_button.custom_minimum_size = Vector2(88.0, 36.0)
	cancel_button.pressed.connect(_cancel)
	footer.add_child(cancel_button)

	var apply_button: Button = Button.new()
	NotLightL10n.bind_text(apply_button, "common.done")
	apply_button.theme_type_variation = "PrimaryButton"
	apply_button.custom_minimum_size = Vector2(92.0, 36.0)
	apply_button.pressed.connect(_commit)
	footer.add_child(apply_button)


func _toggle_advanced_controls() -> void:
	_set_advanced_controls(_advanced_button.button_pressed)


func _set_advanced_controls(enabled: bool) -> void:
	if _picker == null:
		return
	NotLightColorPickerStyle.configure_picker(_picker, _picker.edit_alpha, enabled)
	if _advanced_button != null:
		_advanced_button.set_pressed_no_signal(enabled)
		_advanced_button.text = NotLightL10n.text("color_picker.hide_values") if enabled else NotLightL10n.text("color_picker.show_values")
	if visible:
		call_deferred("_place_inside_viewport")


func _rebuild_swatches(presets: Array[Dictionary]) -> void:
	var signature_parts: PackedStringArray = PackedStringArray()
	for preset: Dictionary in presets:
		var raw_color: Variant = preset.get("color", Color.WHITE)
		if raw_color is Color:
			signature_parts.append("%s:%s" % [str(preset.get("name", "")), (raw_color as Color).to_html(true)])
	var signature: String = "|".join(signature_parts)
	if signature == _swatch_signature:
		return
	_swatch_signature = signature
	for child: Node in _swatch_grid.get_children():
		_swatch_grid.remove_child(child)
		child.queue_free()
	for preset: Dictionary in presets:
		var raw_color: Variant = preset.get("color", Color.WHITE)
		if raw_color is not Color:
			continue
		var color: Color = raw_color as Color
		var button: Button = Button.new()
		button.tooltip_text = str(preset.get("name", color.to_html(false).to_upper()))
		button.custom_minimum_size = Vector2(28.0, 28.0)
		button.focus_mode = Control.FOCUS_NONE
		var normal: StyleBoxFlat = _swatch_style(color, NotLightTheme.semantic_color("border"))
		var hover: StyleBoxFlat = _swatch_style(color.lightened(0.08), NotLightTheme.semantic_color("accent"))
		var pressed: StyleBoxFlat = _swatch_style(color.darkened(0.05), NotLightTheme.semantic_color("accent"))
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", pressed)
		button.pressed.connect(_set_picker_color.bind(color))
		_swatch_grid.add_child(button)


func _set_picker_color(color: Color) -> void:
	_picker.color = color
	# Programmatic ColorPicker assignments are not used as an input signal contract.
	# Refresh the explicit preview so quick swatches always give immediate feedback.
	_update_preview(color)


func _swatch_style(color: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style


func _place_inside_viewport() -> void:
	var available_size: Vector2 = Vector2(
		maxf(1.0, _viewport_size.x - VIEWPORT_MARGIN * 2.0),
		maxf(1.0, _viewport_size.y - VIEWPORT_MARGIN * 2.0)
	)
	var desired_size: Vector2 = Vector2(
		minf(DEFAULT_SIZE.x, available_size.x),
		minf(DEFAULT_SIZE.y, available_size.y)
	)
	# ScrollContainer owns the variable-height middle section, so the header and
	# footer always remain reachable even on the minimum supported viewport.
	desired_size.x = maxf(minf(MINIMUM_USABLE_SIZE.x, available_size.x), desired_size.x)
	desired_size.y = maxf(minf(MINIMUM_USABLE_SIZE.y, available_size.y), desired_size.y)
	size = desired_size
	# Prefer a side placement. Context toolbars generally sit above the object,
	# so a side popover keeps both controls usable instead of stacking on top.
	var right_x: float = _anchor_rect.end.x + ANCHOR_GAP
	var left_x: float = _anchor_rect.position.x - desired_size.x - ANCHOR_GAP
	var x: float
	if right_x + desired_size.x <= _viewport_size.x - VIEWPORT_MARGIN:
		x = right_x
	elif left_x >= VIEWPORT_MARGIN:
		x = left_x
	else:
		x = clampf(_anchor_rect.get_center().x - desired_size.x * 0.5, VIEWPORT_MARGIN, maxf(VIEWPORT_MARGIN, _viewport_size.x - desired_size.x - VIEWPORT_MARGIN))
	var y: float = clampf(_anchor_rect.get_center().y - desired_size.y * 0.35, VIEWPORT_MARGIN, maxf(VIEWPORT_MARGIN, _viewport_size.y - desired_size.y - VIEWPORT_MARGIN))
	position = Vector2(x, y)


func _update_preview(color: Color) -> void:
	if _preview_panel == null or _preview_style == null:
		return
	# This can be called continuously while the picker is manipulated. Mutating one
	# StyleBox avoids allocating/theme-overriding a new resource for every color tick.
	_preview_style.bg_color = color


func _cancel() -> void:
	_picker.color = _initial_color
	visible = false
	canceled.emit()


func _commit() -> void:
	var result: Color = _picker.color
	visible = false
	color_committed.emit(result)
