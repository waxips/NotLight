# SPDX-License-Identifier: GPL-3.0-or-later
class_name ModulePickerPanel
extends PanelContainer

signal module_create_requested(module_id: String)
signal close_requested

var registry: ModuleRegistry
var _search_edit: LineEdit
var _summary_label: Label
var _list: VBoxContainer
var _empty: Label
var _artwork_cache: Dictionary = {}


func _ready() -> void:
	theme_type_variation = "LibraryDrawerPanel"
	clip_contents = false
	_build_ui()
	NotLightL10n.connect_locale_changed(_on_locale_changed)


func _exit_tree() -> void:
	NotLightL10n.disconnect_locale_changed(_on_locale_changed)


func configure(module_registry: ModuleRegistry) -> void:
	if registry != null and registry.modules_changed.is_connected(_refresh):
		registry.modules_changed.disconnect(_refresh)
	registry = module_registry
	if registry != null and not registry.modules_changed.is_connected(_refresh):
		registry.modules_changed.connect(_refresh)
	_refresh()


func focus_search() -> void:
	if _search_edit != null:
		_search_edit.grab_focus()


func _build_ui() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)
	var title_box: VBoxContainer = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	header.add_child(title_box)
	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	title_box.add_child(title_row)
	var title: Label = Label.new()
	NotLightL10n.bind_text(title, "modules.picker.title")
	title.theme_type_variation = "SectionLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var beta: Label = Label.new()
	NotLightL10n.bind_text(beta, "modules.library.beta")
	beta.theme_type_variation = "SettingsValueLabel"
	title_row.add_child(beta)
	_summary_label = Label.new()
	_summary_label.theme_type_variation = "CaptionLabel"
	title_box.add_child(_summary_label)
	var close: Button = Button.new()
	close.icon = load("res://assets/icons/close.svg") as Texture2D
	close.theme_type_variation = "IconButton"
	NotLightL10n.bind_tooltip(close, "common.close")
	close.custom_minimum_size = Vector2(38.0, 38.0)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(close)

	var hint: Label = Label.new()
	NotLightL10n.bind_text(hint, "modules.picker.hint")
	hint.theme_type_variation = "BodyMutedLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)

	_search_edit = LineEdit.new()
	NotLightL10n.bind_placeholder_text(_search_edit, "modules.picker.search")
	_search_edit.clear_button_enabled = true
	_search_edit.custom_minimum_size = Vector2(0.0, 40.0)
	_search_edit.text_changed.connect(func(_text: String) -> void: _refresh())
	root.add_child(_search_edit)

	var divider: HSeparator = HSeparator.new()
	root.add_child(divider)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 9)
	scroll.add_child(_list)
	_empty = Label.new()
	NotLightL10n.bind_text(_empty, "modules.picker.empty")
	_empty.theme_type_variation = "BodyMutedLabel"
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.custom_minimum_size = Vector2(0.0, 96.0)
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_list.add_child(_empty)


func _refresh() -> void:
	if _list == null:
		return
	for child: Node in _list.get_children():
		if child != _empty:
			child.queue_free()
	var active: Array[Dictionary] = []
	if registry != null:
		for info: Dictionary in registry.list_modules():
			if bool(info.get("active", false)) and not bool(info.get("pending_remove", false)):
				active.append(info)
	active.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("name", left.get("module_id", ""))).naturalnocasecmp_to(str(right.get("name", right.get("module_id", "")))) < 0
	)
	var query: String = _search_edit.text.strip_edges().to_lower() if _search_edit != null else ""
	var matching: Array[Dictionary] = []
	for info: Dictionary in active:
		var haystack: String = "%s\n%s\n%s" % [
			str(info.get("name", "")),
			str(info.get("module_id", "")),
			str(info.get("description", "")),
		]
		if query.is_empty() or haystack.to_lower().contains(query):
			matching.append(info)
	_summary_label.text = NotLightL10n.text("modules.picker.summary", {"count": active.size()})
	_empty.visible = matching.is_empty()
	if matching.is_empty() and not query.is_empty():
		NotLightL10n.bind_text(_empty, "common.nothing_found")
	else:
		NotLightL10n.bind_text(_empty, "modules.picker.empty")
	for info: Dictionary in matching:
		_list.add_child(_make_module_card(info))


func _on_locale_changed(_locale: String) -> void:
	NotLightL10n.refresh_tree(self)
	_refresh()


func _make_module_card(info: Dictionary) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var artwork_shell: PanelContainer = PanelContainer.new()
	artwork_shell.custom_minimum_size = Vector2(92.0, 72.0)
	artwork_shell.clip_contents = true
	var artwork_style: StyleBoxFlat = StyleBoxFlat.new()
	artwork_style.bg_color = NotLightTheme.semantic_color("surface_alt")
	artwork_style.border_color = NotLightTheme.semantic_color("border")
	artwork_style.set_border_width_all(1)
	artwork_style.set_corner_radius_all(9)
	artwork_shell.add_theme_stylebox_override("panel", artwork_style)
	row.add_child(artwork_shell)
	var artwork_stack: Control = Control.new()
	artwork_stack.custom_minimum_size = Vector2(92.0, 72.0)
	artwork_shell.add_child(artwork_stack)
	var texture: Texture2D = _artwork_texture_for(info)
	if texture != null:
		var preview: TextureRect = TextureRect.new()
		preview.texture = texture
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		artwork_stack.add_child(preview)
	else:
		var glyph: Label = Label.new()
		glyph.text = "◇"
		glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", 26)
		glyph.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		artwork_stack.add_child(glyph)

	var body: VBoxContainer = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 5)
	row.add_child(body)
	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 7)
	body.add_child(title_row)
	var title: Label = Label.new()
	title.text = str(info.get("name", info.get("module_id", NotLightL10n.text("modules.picker.title"))))
	title.theme_type_variation = "CaptionStrongLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_row.add_child(title)
	var version: Label = Label.new()
	version.text = NotLightL10n.text("ui.format.version") % str(info.get("version", "?"))
	version.theme_type_variation = "CaptionLabel"
	title_row.add_child(version)
	var description: Label = Label.new()
	description.text = str(info.get("description", ""))
	description.theme_type_variation = "CaptionLabel"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.max_lines_visible = 2
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	description.visible = not description.text.is_empty()
	body.add_child(description)
	var action_row: HBoxContainer = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	body.add_child(action_row)
	var module_id: String = str(info.get("module_id", ""))
	var id_label: Label = Label.new()
	id_label.text = module_id
	id_label.theme_type_variation = "CaptionLabel"
	id_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	action_row.add_child(id_label)
	var add_button: Button = Button.new()
	NotLightL10n.bind_text(add_button, "modules.picker.add")
	add_button.theme_type_variation = "PrimaryButton"
	add_button.custom_minimum_size = Vector2(94.0, 34.0)
	add_button.pressed.connect(func() -> void: module_create_requested.emit(module_id))
	action_row.add_child(add_button)
	return card


func _artwork_texture_for(info: Dictionary) -> Texture2D:
	var path: String = str(info.get("preview_path", ""))
	if path.is_empty():
		path = str(info.get("icon_path", ""))
	if path.is_empty():
		return null
	var cached_value: Variant = _artwork_cache.get(path)
	if cached_value is Texture2D:
		return cached_value as Texture2D
	var texture: Texture2D = ModuleArtworkLoader.load_texture(path)
	if texture != null:
		_artwork_cache[path] = texture
	return texture
