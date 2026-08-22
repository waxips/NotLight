# SPDX-License-Identifier: GPL-3.0-or-later
class_name ModuleLibraryInspector
extends PanelContainer

signal close_requested
signal preview_requested(module_id: String)
signal remove_requested(module_id: String, module_name: String, board_count: int)
signal cancel_remove_requested(module_id: String)

const ARTWORK_HEIGHT: float = 250.0

var registry: ModuleRegistry
var _info: Dictionary = {}
var _artwork: TextureRect
var _fallback: CenterContainer
var _preview_button: Button
var _embed_copy_button: Button
var _preview_note: Label
var _title: Label
var _version: Label
var _status: Label
var _description: Label
var _module_id: Label
var _author: Label
var _homepage: Label
var _license: Label
var _runtime: Label
var _storage: Label
var _integrity: Label
var _capabilities: Label
var _usage: Label
var _error: Label
var _action: Button


func _ready() -> void:
	theme_type_variation = "CardPanel"
	_build_ui()
	NotLightL10n.connect_locale_changed(_on_locale_changed)


func _exit_tree() -> void:
	NotLightL10n.disconnect_locale_changed(_on_locale_changed)


func configure(module_registry: ModuleRegistry) -> void:
	registry = module_registry
	_refresh_preview_controls()


func show_module(info: Dictionary, artwork_texture: Texture2D) -> void:
	_info = info.duplicate(true)
	var module_id: String = str(_info.get("module_id", ""))
	var module_name: String = str(_info.get("name", module_id))
	_title.text = module_name
	_version.text = NotLightL10n.text("ui.format.version") % str(_info.get("version", "?"))
	_status.text = _status_text(_info)
	_apply_status_color(_status, _info)
	_description.text = str(_info.get("description", ""))
	_description.visible = not _description.text.is_empty()
	_module_id.text = module_id
	_author.text = _value_or_fallback(str(_info.get("author", "")))
	_homepage.text = _value_or_fallback(str(_info.get("homepage", "")))
	_license.text = _value_or_fallback(str(_info.get("license", "")))
	_runtime.text = NotLightL10n.text("modules.library.inspector.runtime_value", {
		"api": int(_info.get("module_api_version", 0)),
		"godot": str(_info.get("godot_version", "?")),
		"schema": int(_info.get("state_schema_version", 0)),
		"kind": str(_info.get("kind", "code")),
	})
	_storage.text = NotLightL10n.text("modules.library.inspector.storage_value", {
		"installed": _format_bytes(int(_info.get("byte_size", 0))),
		"payload": _format_bytes(int(_info.get("payload_byte_size", 0))),
	})
	var package_hash: String = str(_info.get("source_package_sha256", ""))
	var payload_hash: String = str(_info.get("payload_sha256", ""))
	_integrity.text = NotLightL10n.text("modules.library.inspector.integrity_value", {
		"package": _short_hash(package_hash),
		"payload": _short_hash(payload_hash),
	})
	_capabilities.text = _capability_text(_info)
	_usage.text = _usage_text(_info)
	var error_text: String = str(_info.get("last_error", ""))
	_error.visible = not error_text.is_empty()
	_error.text = error_text
	_artwork.texture = artwork_texture
	_show_static_preview()
	if bool(_info.get("pending_remove", false)):
		NotLightL10n.bind_text(_action, "modules.library.cancel_remove")
		_action.theme_type_variation = "GhostButton"
	else:
		NotLightL10n.bind_text(_action, "modules.library.remove")
		_action.theme_type_variation = "DangerButton"
	_action.set_meta("module_id", module_id)
	_action.set_meta("module_name", module_name)
	_action.set_meta("boards", int(_info.get("boards_used_count", 0)))
	_refresh_preview_controls()


func clear_module() -> void:
	_info = {}
	if _artwork != null:
		_artwork.texture = null
	_show_static_preview()
	_refresh_preview_controls()


func _build_ui() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)
	var heading: VBoxContainer = VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 1)
	header.add_child(heading)
	_title = Label.new()
	_title.theme_type_variation = "SectionLabel"
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_child(_title)
	var version_row: HBoxContainer = HBoxContainer.new()
	version_row.add_theme_constant_override("separation", 8)
	heading.add_child(version_row)
	_version = Label.new()
	_version.theme_type_variation = "CaptionLabel"
	version_row.add_child(_version)
	_status = Label.new()
	_status.theme_type_variation = "SettingsValueLabel"
	version_row.add_child(_status)
	var close_button: Button = Button.new()
	close_button.icon = load("res://assets/icons/close.svg") as Texture2D
	close_button.theme_type_variation = "IconButton"
	close_button.custom_minimum_size = Vector2(38.0, 38.0)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(close_button)

	# All developer-owned metadata belongs to one body scroller. Keeping artwork,
	# preview controls and details in separate fixed regions made the details
	# scroller collapse to only one or two rows on laptop-height windows, which
	# made fields such as author/homepage look absent even when they existed.
	var body_scroll: ScrollContainer = ScrollContainer.new()
	body_scroll.name = "ModuleInspectorBodyScroll"
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.custom_minimum_size = Vector2(0.0, 220.0)
	root.add_child(body_scroll)
	var vertical_bar: VScrollBar = body_scroll.get_v_scroll_bar()
	vertical_bar.theme_type_variation = "NoteScrollBar"
	vertical_bar.custom_minimum_size = Vector2(11.0, 0.0)
	var body: VBoxContainer = VBoxContainer.new()
	body.name = "ModuleInspectorBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	body_scroll.add_child(body)

	var artwork_shell: PanelContainer = PanelContainer.new()
	artwork_shell.custom_minimum_size = Vector2(0.0, ARTWORK_HEIGHT)
	artwork_shell.clip_contents = true
	artwork_shell.add_theme_stylebox_override("panel", _preview_style())
	body.add_child(artwork_shell)
	var artwork_stack: Control = Control.new()
	artwork_stack.custom_minimum_size = Vector2(0.0, ARTWORK_HEIGHT)
	artwork_shell.add_child(artwork_stack)
	_artwork = TextureRect.new()
	_artwork.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artwork_stack.add_child(_artwork)
	_fallback = CenterContainer.new()
	_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artwork_stack.add_child(_fallback)
	var fallback_mark: Label = Label.new()
	fallback_mark.text = "◇"
	fallback_mark.add_theme_font_size_override("font_size", 46)
	fallback_mark.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
	_fallback.add_child(fallback_mark)

	var preview_actions: HBoxContainer = HBoxContainer.new()
	preview_actions.add_theme_constant_override("separation", 8)
	body.add_child(preview_actions)
	_preview_button = Button.new()
	NotLightL10n.bind_text(_preview_button, "modules.library.preview.start")
	_preview_button.theme_type_variation = "PrimaryButton"
	_preview_button.custom_minimum_size = Vector2(0.0, 40.0)
	_preview_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_button.pressed.connect(_request_preview)
	preview_actions.add_child(_preview_button)
	_embed_copy_button = Button.new()
	NotLightL10n.bind_text(_embed_copy_button, "modules.library.embed.copy")
	_embed_copy_button.theme_type_variation = "GhostButton"
	_embed_copy_button.custom_minimum_size = Vector2(128.0, 40.0)
	_embed_copy_button.pressed.connect(_copy_embed_syntax)
	preview_actions.add_child(_embed_copy_button)
	_preview_note = Label.new()
	_preview_note.theme_type_variation = "CaptionLabel"
	_preview_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_preview_note)

	_description = Label.new()
	_description.theme_type_variation = "BodyMutedLabel"
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_description)

	var notice: Label = Label.new()
	NotLightL10n.bind_text(notice, "modules.library.inspector.developer_metadata")
	notice.theme_type_variation = "CaptionLabel"
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
	body.add_child(notice)

	var details: VBoxContainer = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 10)
	body.add_child(details)
	_module_id = _add_detail(details, "modules.library.inspector.module_id")
	_author = _add_detail(details, "modules.library.inspector.author")
	_homepage = _add_detail(details, "modules.library.inspector.homepage")
	_license = _add_detail(details, "modules.library.inspector.license")
	_runtime = _add_detail(details, "modules.library.inspector.runtime")
	_storage = _add_detail(details, "modules.library.inspector.storage")
	_integrity = _add_detail(details, "modules.library.inspector.integrity")
	_capabilities = _add_detail(details, "modules.library.inspector.capabilities")
	_usage = _add_detail(details, "modules.library.inspector.usage")

	_error = Label.new()
	_error.theme_type_variation = "CaptionLabel"
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.add_theme_color_override("font_color", NotLightTheme.semantic_color("danger"))
	body.add_child(_error)

	# Destructive install state stays pinned below the scrollable developer data.
	_action = Button.new()
	_action.custom_minimum_size = Vector2(0.0, 40.0)
	_action.pressed.connect(_on_action_pressed)
	root.add_child(_action)
	_refresh_preview_controls()


func _add_detail(parent: VBoxContainer, title_key: String) -> Label:
	var block: VBoxContainer = VBoxContainer.new()
	block.add_theme_constant_override("separation", 2)
	parent.add_child(block)
	var title: Label = Label.new()
	NotLightL10n.bind_text(title, title_key)
	title.theme_type_variation = "CaptionStrongLabel"
	block.add_child(title)
	var value: Label = Label.new()
	value.theme_type_variation = "CaptionLabel"
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	block.add_child(value)
	return value


func _copy_embed_syntax() -> void:
	var module_id: String = str(_info.get("module_id", "")).strip_edges().to_lower()
	var syntax: String = NoteModuleEmbed.syntax_for_module(module_id)
	if syntax.is_empty():
		return
	DisplayServer.clipboard_set(syntax)
	_set_preview_note(NotLightL10n.text("modules.library.embed.copied", {"syntax": syntax}), false)


func _request_preview() -> void:
	var module_id: String = str(_info.get("module_id", "")).strip_edges().to_lower()
	if module_id.is_empty() or registry == null:
		_set_preview_note(NotLightL10n.text("modules.library.preview.unavailable"), true)
		return
	if not _preview_available(module_id):
		_set_preview_note(NotLightL10n.text("modules.library.preview.restart_required"), true)
		return
	preview_requested.emit(module_id)


func _show_static_preview() -> void:
	if _artwork == null or _fallback == null:
		return
	var has_artwork: bool = _artwork.texture != null
	_artwork.visible = has_artwork
	_fallback.visible = not has_artwork


func _refresh_preview_controls() -> void:
	if _preview_button == null or _preview_note == null or _embed_copy_button == null:
		return
	if _info.is_empty():
		_preview_button.disabled = true
		_embed_copy_button.disabled = true
		_preview_note.text = ""
		_preview_note.visible = false
		return
	var module_id: String = str(_info.get("module_id", "")).strip_edges().to_lower()
	var available: bool = _preview_available(module_id)
	_preview_button.disabled = not available
	_embed_copy_button.disabled = not ModuleManifest.is_valid_module_id(module_id)
	if available:
		_set_preview_note(NotLightL10n.text("modules.library.preview.ephemeral"), false)
	else:
		_set_preview_note(NotLightL10n.text("modules.library.preview.restart_required"), false)


func _preview_available(module_id: String) -> bool:
	if registry == null or module_id.is_empty():
		return false
	if bool(_info.get("pending_remove", false)):
		return false
	return bool(_info.get("active", false)) and registry.is_module_active(module_id)


func _set_preview_note(text: String, is_error: bool) -> void:
	if _preview_note == null:
		return
	_preview_note.text = text
	_preview_note.visible = not text.is_empty()
	_preview_note.remove_theme_color_override("font_color")
	_preview_note.add_theme_color_override(
		"font_color",
		NotLightTheme.semantic_color("danger") if is_error else NotLightTheme.semantic_color("text_muted")
	)


func _on_locale_changed(_locale: String) -> void:
	var module_id: String = str(_info.get("module_id", "")).strip_edges().to_lower()
	if registry != null and not module_id.is_empty():
		var localized_info: Dictionary = registry.get_known_module_info(module_id)
		if not localized_info.is_empty():
			var artwork_texture: Texture2D = null
			if _artwork != null:
				artwork_texture = _artwork.texture
			show_module(localized_info, artwork_texture)
			return
	_refresh_preview_controls()


func _on_action_pressed() -> void:
	var module_id: String = str(_action.get_meta("module_id", ""))
	if module_id.is_empty():
		return
	if bool(_info.get("pending_remove", false)):
		cancel_remove_requested.emit(module_id)
	else:
		remove_requested.emit(
			module_id,
			str(_action.get_meta("module_name", module_id)),
			int(_action.get_meta("boards", 0))
		)


func _capability_text(info: Dictionary) -> String:
	var value: Variant = info.get("capabilities", [])
	if value is not Array or (value as Array).is_empty():
		return NotLightL10n.text("modules.library.inspector.none")
	var capabilities: PackedStringArray = PackedStringArray()
	for raw_capability: Variant in value as Array:
		capabilities.append(str(raw_capability))
	return "\n".join(capabilities)


func _usage_text(info: Dictionary) -> String:
	var boards_value: Variant = info.get("boards_used", [])
	if boards_value is not Array or (boards_value as Array).is_empty():
		return NotLightL10n.text("modules.library.inspector.not_used")
	var names: PackedStringArray = PackedStringArray()
	for raw_board: Variant in boards_value as Array:
		if raw_board is Dictionary:
			names.append(str((raw_board as Dictionary).get("name", NotLightL10n.text("modules.library.board_fallback"))))
	return "\n".join(names)


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


func _preview_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = NotLightTheme.semantic_color("surface_alt")
	style.border_color = NotLightTheme.semantic_color("border")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	return style


static func _value_or_fallback(value: String) -> String:
	var clean: String = value.strip_edges()
	return clean if not clean.is_empty() else NotLightL10n.text("performance.unavailable")


static func _short_hash(value: String) -> String:
	var clean: String = value.strip_edges().to_lower()
	if clean.length() < 16:
		return NotLightL10n.text("performance.unavailable")
	return NotLightL10n.text("ui.format.short_hash") % [clean.substr(0, 10), clean.substr(clean.length() - 8, 8)]


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
