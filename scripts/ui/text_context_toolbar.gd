# SPDX-License-Identifier: GPL-3.0-or-later
class_name TextContextToolbar
extends PanelContainer

signal edit_requested
signal delete_requested
signal font_family_requested(font_family: String)
signal font_size_requested(font_size: float)
signal font_style_requested(style_flag: int, enabled: bool)
signal alignment_requested(alignment: HorizontalAlignment)
signal list_type_requested(list_type: int)
signal list_indent_requested(delta: int)
signal text_color_requested(color: Color)
signal background_color_requested(color: Color)
signal text_color_picker_requested(anchor_rect: Rect2, current_color: Color)
signal background_color_picker_requested(anchor_rect: Rect2, current_color: Color)
signal background_opacity_requested(opacity: float)

const FONT_SIZE_OPTIONS: Array[int] = [10, 12, 14, 16, 18, 20, 22, 24, 28, 32, 36, 42, 48, 56, 64, 72, 80, 96, 120, 144, 192, 288]
const VIEWPORT_MARGIN: float = 18.0
const TOP_UI_SAFE_Y: float = 92.0
const ANCHOR_GAP: float = 14.0
const OPACITY_ID_BASE: int = 10000

const TEXT_PALETTE_PRESETS: Array[Dictionary] = [
	{"name_key": "formula.color.graphite", "color": Color("#243129")},
	{"name_key": "formula.color.green", "color": Color("#237a4b")},
	{"name_key": "formula.color.blue", "color": Color("#3568c8")},
	{"name_key": "formula.color.purple", "color": Color("#7656c9")},
	{"name_key": "formula.color.red", "color": Color("#b94a48")},
	{"name_key": "runtime.ui.connector_context_toolbar.6494ce14e1", "color": Color("#b7662d")},
	{"name_key": "runtime.ui.text_context_toolbar.8db0f15e2e", "color": Color("#fffef9")},
]

const BACKGROUND_PALETTE_PRESETS: Array[Dictionary] = [
	{"name_key": "runtime.ui.text_context_toolbar.dbccea80f0", "color": Color("#e8f4e8")},
	{"name_key": "runtime.ui.text_context_toolbar.a2859e43ff", "color": Color("#fff2b8")},
	{"name_key": "runtime.ui.text_context_toolbar.ac0fc9a127", "color": Color("#e5eefb")},
	{"name_key": "runtime.ui.text_context_toolbar.6f8ecf4df4", "color": Color("#f8e2e6")},
	{"name_key": "runtime.ui.text_context_toolbar.3762658f32", "color": Color("#eee7f8")},
	{"name_key": "runtime.ui.text_context_toolbar.1f3c140e1a", "color": Color("#ecece7")},
]

var _font_families: PackedStringArray = PackedStringArray()
var _font_family_menu: MenuButton
var _font_size_menu: MenuButton
var _edit_button: Button
var _text_color_picker: Button
var _background_picker: Button
var _opacity_menu: MenuButton
var _alignment_buttons: Dictionary = {}
var _style_buttons: Dictionary = {}
var _list_buttons: Dictionary = {}
var _updating: bool = false
var _has_context: bool = false
var _anchor_should_show: bool = false
var _anchor_rect: Rect2 = Rect2()
var _viewport_size: Vector2 = Vector2.ZERO
var _current_background: Color = Color.TRANSPARENT
var _pending_text_color: Color = TextBlockStore.COLOR_TEXT
var _pending_background_color: Color = Color.TRANSPARENT
var _editor_context_active: bool = false


static func text_palette() -> Array[Dictionary]:
	return _localized_palette(TEXT_PALETTE_PRESETS, TextBlockStore.COLOR_TEXT)


static func background_palette() -> Array[Dictionary]:
	return _localized_palette(BACKGROUND_PALETTE_PRESETS, Color.TRANSPARENT)


static func _localized_palette(presets: Array[Dictionary], fallback_color: Color) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for preset: Dictionary in presets:
		result.append({
			"name": NotLightL10n.text(str(preset.get("name_key", ""))),
			"color": preset.get("color", fallback_color),
		})
	return result


func _ready() -> void:
	theme_type_variation = "FloatingPanel"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 160
	_build_ui()


func update_context(
	runtime: BoardRuntime,
	selected_ids: PackedInt64Array,
	editor_entity_id: int,
	editor_context: Dictionary = {}
) -> void:
	if runtime == null:
		_has_context = false
		_apply_visibility()
		return
	var text_ids: PackedInt64Array = PackedInt64Array()
	if editor_entity_id > 0 and runtime.model.text_blocks.contains(editor_entity_id):
		text_ids.append(editor_entity_id)
	else:
		for entity_id: int in selected_ids:
			if runtime.model.get_entity_type(entity_id) == BoardEntityTypes.TEXT and runtime.model.text_blocks.contains(entity_id):
				text_ids.append(entity_id)
	if text_ids.is_empty():
		_has_context = false
		_apply_visibility()
		return
	_has_context = true
	_updating = true
	var primary_id: int = editor_entity_id if editor_entity_id > 0 else runtime.selection.primary_id
	if not runtime.model.text_blocks.contains(primary_id):
		primary_id = int(text_ids[0])
	var record: Dictionary = runtime.model.text_blocks.get_record(primary_id)
	var context: Dictionary = editor_context if not editor_context.is_empty() else _context_from_record(record)
	_editor_context_active = editor_entity_id > 0
	_font_family_menu.text = str(context.get("font_family", TextBlockStore.DEFAULT_FONT_FAMILY))
	NotLightL10n.bind_tooltip(_font_family_menu, "asset.kind.font")
	_font_size_menu.text = NotLightL10n.text("ui.format.integer") % int(round(float(context.get("font_size", TextBlockStore.DEFAULT_FONT_SIZE))))
	NotLightL10n.bind_tooltip(_font_size_menu, "runtime.ui.text_context_toolbar.03b49f21ad")
	var alignment: int = int(context.get("alignment", HORIZONTAL_ALIGNMENT_LEFT))
	for key: Variant in _alignment_buttons.keys():
		var button: Button = _alignment_buttons[key] as Button
		button.set_pressed_no_signal(int(key) == alignment)
	var style_flags: int = int(context.get("style_flags", int(record.get("base_style_flags", 0))))
	for key: Variant in _style_buttons.keys():
		var style_button: Button = _style_buttons[key] as Button
		style_button.set_pressed_no_signal((style_flags & int(key)) != 0)
	var list_type: int = int(context.get("list_type", TextBlockStore.LIST_NONE))
	for key: Variant in _list_buttons.keys():
		var list_button: Button = _list_buttons[key] as Button
		list_button.set_pressed_no_signal(int(key) == list_type)
	var text_color: Color = _variant_to_color(context.get("text_color", record.get("text_color", TextBlockStore.COLOR_TEXT.to_html(true))), TextBlockStore.COLOR_TEXT)
	_current_background = _variant_to_color(context.get("background_color", record.get("background_color", Color.TRANSPARENT.to_html(true))), Color.TRANSPARENT)
	_pending_text_color = text_color
	_pending_background_color = _current_background
	_update_text_color_button(text_color)
	_update_background_color_button(_current_background)
	_opacity_menu.text = NotLightL10n.text("ui.format.percent_int") % int(round(_current_background.a * 100.0))
	NotLightL10n.bind_tooltip(_opacity_menu, "runtime.ui.board_screen.bd7b345fcd")
	_edit_button.disabled = text_ids.size() != 1 or editor_entity_id > 0
	_updating = false
	_apply_visibility()


func set_toolbar_anchor(screen_rect: Rect2, viewport_size: Vector2, should_show: bool) -> void:
	_anchor_rect = screen_rect
	_viewport_size = viewport_size
	_anchor_should_show = should_show
	_apply_visibility()


func _apply_visibility() -> void:
	visible = _has_context and _anchor_should_show and _anchor_rect.has_area()
	if not visible:
		return
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

	var type_label: Label = Label.new()
	type_label.text = "T"
	NotLightL10n.bind_tooltip(type_label, "runtime.ui.text_context_toolbar.7dcceeb6cd")
	type_label.theme_type_variation = "TitleLabel"
	type_label.custom_minimum_size = Vector2(34.0, 40.0)
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(type_label)
	row.add_child(_separator())

	_font_family_menu = MenuButton.new()
	_prepare_toolbar_button(_font_family_menu, "GhostButton", Vector2(142.0, 40.0))
	_font_families = TextFontRegistry.available_font_families()
	var font_popup: PopupMenu = _font_family_menu.get_popup()
	for index: int in range(_font_families.size()):
		font_popup.add_item(_font_families[index], index)
	font_popup.id_pressed.connect(_on_font_family_selected)
	row.add_child(_font_family_menu)

	_font_size_menu = MenuButton.new()
	_prepare_toolbar_button(_font_size_menu, "GhostButton", Vector2(58.0, 40.0))
	var size_popup: PopupMenu = _font_size_menu.get_popup()
	for font_size: int in FONT_SIZE_OPTIONS:
		size_popup.add_item(str(font_size), font_size)
	size_popup.id_pressed.connect(_on_font_size_selected)
	row.add_child(_font_size_menu)
	row.add_child(_separator())

	_add_style_button(row, TextBlockStore.FONT_STYLE_BOLD, "B", "runtime.ui.text_context_toolbar.903a2e24e9")
	_add_style_button(row, TextBlockStore.FONT_STYLE_ITALIC, "I", "runtime.ui.text_context_toolbar.dd4fca0c5e")
	_add_style_button(row, TextBlockStore.FONT_STYLE_UNDERLINE, "U", "runtime.ui.text_context_toolbar.e71a26473a")
	_add_style_button(row, TextBlockStore.FONT_STYLE_STRIKETHROUGH, "S", "runtime.ui.text_context_toolbar.60cad45c36")
	row.add_child(_separator())

	var alignment_group: ButtonGroup = ButtonGroup.new()
	_add_alignment_button(row, HORIZONTAL_ALIGNMENT_LEFT, "res://assets/icons/align_left.svg", "runtime.ui.text_context_toolbar.f000fb2aeb", alignment_group)
	_add_alignment_button(row, HORIZONTAL_ALIGNMENT_CENTER, "res://assets/icons/align_center.svg", "runtime.ui.text_context_toolbar.fd17e2f9ce", alignment_group)
	_add_alignment_button(row, HORIZONTAL_ALIGNMENT_RIGHT, "res://assets/icons/align_right.svg", "runtime.ui.text_context_toolbar.62c772a0cb", alignment_group)
	row.add_child(_separator())

	_add_list_button(row, TextBlockStore.LIST_BULLET, "•", "runtime.ui.text_context_toolbar.00804663b6")
	_add_list_button(row, TextBlockStore.LIST_NUMBERED, "1.", "runtime.ui.text_context_toolbar.f3d4162386")
	var outdent_button: Button = Button.new()
	outdent_button.text = "‹"
	NotLightL10n.bind_tooltip(outdent_button, "runtime.ui.text_context_toolbar.827a7562b6")
	_prepare_toolbar_button(outdent_button, "IconButton", Vector2(34.0, 40.0))
	outdent_button.pressed.connect(func() -> void: list_indent_requested.emit(-1))
	row.add_child(outdent_button)
	var indent_button: Button = Button.new()
	indent_button.text = "›"
	NotLightL10n.bind_tooltip(indent_button, "runtime.ui.text_context_toolbar.e4f9c50b6d")
	_prepare_toolbar_button(indent_button, "IconButton", Vector2(34.0, 40.0))
	indent_button.pressed.connect(func() -> void: list_indent_requested.emit(1))
	row.add_child(indent_button)
	row.add_child(_separator())

	_text_color_picker = Button.new()
	_text_color_picker.text = "A"
	_prepare_toolbar_button(_text_color_picker, "IconButton", Vector2(42.0, 40.0))
	_text_color_picker.pressed.connect(func() -> void:
		text_color_picker_requested.emit(_text_color_picker.get_global_rect(), _pending_text_color)
	)
	row.add_child(_text_color_picker)

	_background_picker = Button.new()
	_background_picker.text = "▣"
	_prepare_toolbar_button(_background_picker, "IconButton", Vector2(42.0, 40.0))
	_background_picker.pressed.connect(func() -> void:
		background_color_picker_requested.emit(_background_picker.get_global_rect(), _current_background)
	)
	row.add_child(_background_picker)

	_opacity_menu = MenuButton.new()
	_prepare_toolbar_button(_opacity_menu, "GhostButton", Vector2(58.0, 40.0))
	var opacity_popup: PopupMenu = _opacity_menu.get_popup()
	for percent: int in [0, 20, 40, 60, 80, 100]:
		opacity_popup.add_item(NotLightL10n.text("ui.format.percent_int") % percent, OPACITY_ID_BASE + percent)
	opacity_popup.id_pressed.connect(_on_opacity_selected)
	row.add_child(_opacity_menu)
	row.add_child(_separator())

	_edit_button = Button.new()
	_edit_button.icon = load("res://assets/icons/edit.svg") as Texture2D
	NotLightL10n.bind_tooltip(_edit_button, "runtime.ui.text_context_toolbar.18dee16e21")
	_prepare_toolbar_button(_edit_button, "IconButton", Vector2(40.0, 40.0))
	_edit_button.pressed.connect(func() -> void: edit_requested.emit())
	row.add_child(_edit_button)

	var delete_button: Button = Button.new()
	delete_button.icon = load("res://assets/icons/trash.svg") as Texture2D
	NotLightL10n.bind_tooltip(delete_button, "runtime.ui.text_context_toolbar.a500089728")
	_prepare_toolbar_button(delete_button, "DangerIconButton", Vector2(40.0, 40.0))
	delete_button.pressed.connect(func() -> void: delete_requested.emit())
	row.add_child(delete_button)


func _prepare_toolbar_button(button: BaseButton, variation: String, minimum_size: Vector2) -> void:
	button.theme_type_variation = variation
	button.custom_minimum_size = minimum_size
	button.focus_mode = Control.FOCUS_NONE


func _on_font_family_selected(id: int) -> void:
	if _updating or id < 0 or id >= _font_families.size():
		return
	font_family_requested.emit(_font_families[id])


func _on_font_size_selected(id: int) -> void:
	if _updating:
		return
	font_size_requested.emit(clampf(float(id), TextBlockStore.MIN_FONT_SIZE, TextBlockStore.MAX_FONT_SIZE))


func _add_alignment_button(
	row: HBoxContainer,
	alignment: HorizontalAlignment,
	icon_path: String,
	tooltip_key: String,
	group: ButtonGroup
) -> void:
	var button: Button = Button.new()
	button.icon = load(icon_path) as Texture2D
	NotLightL10n.bind_tooltip(button, tooltip_key)
	button.toggle_mode = true
	button.button_group = group
	_prepare_toolbar_button(button, "IconButton", Vector2(36.0, 40.0))
	button.pressed.connect(func() -> void:
		if not _updating:
			alignment_requested.emit(alignment)
	)
	_alignment_buttons[int(alignment)] = button
	row.add_child(button)


func _add_style_button(row: HBoxContainer, flag: int, label: String, tooltip_key: String) -> void:
	var button: Button = Button.new()
	button.text = label
	NotLightL10n.bind_tooltip(button, tooltip_key)
	button.toggle_mode = true
	_prepare_toolbar_button(button, "IconButton", Vector2(36.0, 40.0))
	button.toggled.connect(func(enabled: bool) -> void:
		if not _updating:
			font_style_requested.emit(flag, enabled)
	)
	_style_buttons[flag] = button
	row.add_child(button)


func _add_list_button(row: HBoxContainer, list_type: int, label: String, tooltip_key: String) -> void:
	var button: Button = Button.new()
	button.text = label
	NotLightL10n.bind_tooltip(button, tooltip_key)
	button.toggle_mode = true
	_prepare_toolbar_button(button, "IconButton", Vector2(38.0, 40.0))
	button.toggled.connect(func(enabled: bool) -> void:
		if _updating:
			return
		if enabled:
			_updating = true
			for other_key: Variant in _list_buttons.keys():
				if int(other_key) == list_type:
					continue
				var other_button: Button = _list_buttons[other_key] as Button
				other_button.set_pressed_no_signal(false)
			_updating = false
		list_type_requested.emit(list_type if enabled else TextBlockStore.LIST_NONE)
	)
	_list_buttons[list_type] = button
	row.add_child(button)


func apply_text_color_from_popover(color: Color) -> void:
	_pending_text_color = color
	_update_text_color_button(color)
	text_color_requested.emit(color)


func apply_background_color_from_popover(color: Color) -> void:
	_pending_background_color = color
	_current_background = color
	_update_background_color_button(color)
	_opacity_menu.text = NotLightL10n.text("ui.format.percent_int") % int(round(color.a * 100.0))
	background_color_requested.emit(color)


func _update_text_color_button(color: Color) -> void:
	if _text_color_picker == null:
		return
	_text_color_picker.tooltip_text = NotLightL10n.text("runtime.ui.text_context_toolbar.03afb35ff2") % color.to_html(false).to_upper()
	_text_color_picker.add_theme_color_override("font_color", color)
	_text_color_picker.add_theme_color_override("font_hover_color", color)
	_text_color_picker.add_theme_color_override("font_pressed_color", color)


func _update_background_color_button(color: Color) -> void:
	if _background_picker == null:
		return
	_background_picker.tooltip_text = NotLightL10n.text("runtime.ui.text_context_toolbar.80b8552d80") % color.to_html(true).to_upper()
	var display_color: Color = color
	if display_color.a <= 0.02:
		display_color = NotLightTheme.semantic_color("text_muted")
	_background_picker.add_theme_color_override("font_color", display_color)
	_background_picker.add_theme_color_override("font_hover_color", display_color)
	_background_picker.add_theme_color_override("font_pressed_color", display_color)


func _on_opacity_selected(id: int) -> void:
	if _updating or id < OPACITY_ID_BASE:
		return
	var percent: int = clampi(id - OPACITY_ID_BASE, 0, 100)
	background_opacity_requested.emit(float(percent) / 100.0)


func _context_from_record(record: Dictionary) -> Dictionary:
	var paragraphs: Array = record.get("paragraphs", []) as Array
	var list_type: int = TextBlockStore.LIST_NONE
	if not paragraphs.is_empty() and paragraphs[0] is Dictionary:
		list_type = int((paragraphs[0] as Dictionary).get("list_type", TextBlockStore.LIST_NONE))
	return {
		"font_family": str(record.get("font_family", TextBlockStore.DEFAULT_FONT_FAMILY)),
		"font_size": float(record.get("font_size", TextBlockStore.DEFAULT_FONT_SIZE)),
		"alignment": int(record.get("alignment", HORIZONTAL_ALIGNMENT_LEFT)),
		"style_flags": int(record.get("base_style_flags", 0)),
		"text_color": str(record.get("text_color", TextBlockStore.COLOR_TEXT.to_html(true))),
		"background_color": str(record.get("background_color", Color.TRANSPARENT.to_html(true))),
		"list_type": list_type,
	}


func _variant_to_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value as Color
	return Color.from_string(str(value), fallback)


func _separator() -> VSeparator:
	var separator: VSeparator = VSeparator.new()
	separator.custom_minimum_size = Vector2(4.0, 30.0)
	return separator
