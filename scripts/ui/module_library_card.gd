# SPDX-License-Identifier: GPL-3.0-or-later
class_name ModuleLibraryCard
extends PanelContainer

signal inspect_requested(module_id: String)

const CARD_WIDTH: float = 236.0
const ARTWORK_HEIGHT: float = 126.0

var _module_id: String = ""
var _artwork: TextureRect
var _fallback_mark: Label
var _title: Label
var _version: Label
var _status: Label
var _description: Label
var _meta: Label
var _details_button: Button


func _ready() -> void:
	theme_type_variation = "CardPanel"
	custom_minimum_size = Vector2(CARD_WIDTH, 282.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_ALL
	gui_input.connect(_on_card_gui_input)
	_build_ui()


func configure(info: Dictionary, artwork_texture: Texture2D) -> void:
	_module_id = str(info.get("module_id", ""))
	set_meta("module_id", _module_id)
	var module_name: String = str(info.get("name", _module_id))
	_title.text = module_name
	_version.text = NotLightL10n.text("ui.format.version") % str(info.get("version", "?"))
	_status.text = _status_text(info)
	_apply_status_color(_status, info)
	_description.text = str(info.get("description", ""))
	_description.visible = not _description.text.is_empty()
	_meta.text = NotLightL10n.text("modules.library.card_meta_compact", {
		"size": _format_bytes(int(info.get("byte_size", 0))),
		"boards": int(info.get("boards_used_count", 0)),
	})
	_artwork.texture = artwork_texture
	_artwork.visible = artwork_texture != null
	_fallback_mark.visible = artwork_texture == null
	_details_button.disabled = _module_id.is_empty()
	tooltip_text = module_name


func set_selected(selected: bool) -> void:
	if selected:
		add_theme_stylebox_override("panel", _selected_style())
	else:
		remove_theme_stylebox_override("panel")


func _build_ui() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var artwork_shell: PanelContainer = PanelContainer.new()
	artwork_shell.custom_minimum_size = Vector2(0.0, ARTWORK_HEIGHT)
	artwork_shell.clip_contents = true
	artwork_shell.add_theme_stylebox_override("panel", _artwork_style())
	root.add_child(artwork_shell)
	var artwork_stack: Control = Control.new()
	artwork_stack.custom_minimum_size = Vector2(0.0, ARTWORK_HEIGHT)
	artwork_shell.add_child(artwork_stack)
	_artwork = TextureRect.new()
	_artwork.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artwork_stack.add_child(_artwork)
	_fallback_mark = Label.new()
	_fallback_mark.text = "◇"
	_fallback_mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fallback_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fallback_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fallback_mark.add_theme_font_size_override("font_size", 42)
	_fallback_mark.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
	_fallback_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artwork_stack.add_child(_fallback_mark)

	var heading: HBoxContainer = HBoxContainer.new()
	heading.add_theme_constant_override("separation", 6)
	root.add_child(heading)
	_title = Label.new()
	_title.theme_type_variation = "CaptionStrongLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_child(_title)
	_version = Label.new()
	_version.theme_type_variation = "CaptionLabel"
	heading.add_child(_version)

	_status = Label.new()
	_status.theme_type_variation = "SettingsValueLabel"
	root.add_child(_status)

	_description = Label.new()
	_description.theme_type_variation = "CaptionLabel"
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.max_lines_visible = 2
	_description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(_description)

	_meta = Label.new()
	_meta.theme_type_variation = "CaptionLabel"
	_meta.add_theme_color_override("font_color", NotLightTheme.semantic_color("text_muted"))
	root.add_child(_meta)

	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)
	_details_button = Button.new()
	NotLightL10n.bind_text(_details_button, "modules.library.details")
	_details_button.theme_type_variation = "GhostButton"
	_details_button.custom_minimum_size = Vector2(0.0, 34.0)
	_details_button.pressed.connect(_emit_inspect)
	root.add_child(_details_button)


func _on_card_gui_input(event: InputEvent) -> void:
	if _module_id.is_empty():
		return
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_emit_inspect()
			accept_event()
	elif event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and (key_event.keycode == KEY_ENTER or key_event.keycode == KEY_SPACE):
			_emit_inspect()
			accept_event()


func _emit_inspect() -> void:
	if not _module_id.is_empty():
		inspect_requested.emit(_module_id)


func _status_text(info: Dictionary) -> String:
	if bool(info.get("pending_remove", false)):
		return NotLightL10n.text("modules.library.status_remove")
	if not str(info.get("pending_version_key", "")).is_empty():
		return NotLightL10n.text("modules.library.status_restart")
	if bool(info.get("active", false)):
		return NotLightL10n.text("modules.library.status_active")
	return NotLightL10n.text("modules.library.status_inactive")


func _apply_status_color(label: Label, info: Dictionary) -> void:
	label.remove_theme_color_override("font_color")
	if bool(info.get("pending_remove", false)) or not str(info.get("last_error", "")).is_empty():
		label.add_theme_color_override("font_color", NotLightTheme.semantic_color("danger"))
	elif bool(info.get("active", false)):
		label.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
	else:
		label.add_theme_color_override("font_color", NotLightTheme.semantic_color("text_muted"))


func _artwork_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = NotLightTheme.semantic_color("surface_alt")
	style.border_color = NotLightTheme.semantic_color("border")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	return style


func _selected_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = NotLightTheme.semantic_color("surface")
	style.border_color = NotLightTheme.semantic_color("accent")
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.10)
	style.shadow_size = 5
	return style


static func _format_bytes(byte_size: int) -> String:
	var value: float = float(maxi(0, byte_size))
	if value < 1024.0:
		return NotLightL10n.text("ui.format.bytes_b") % int(value)
	value /= 1024.0
	if value < 1024.0:
		return NotLightL10n.text("ui.format.bytes_kib") % value
	value /= 1024.0
	if value < 1024.0:
		return NotLightL10n.text("ui.format.bytes_mib") % value
	return NotLightL10n.text("ui.format.bytes_gib") % (value / 1024.0)
