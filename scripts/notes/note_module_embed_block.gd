# SPDX-License-Identifier: GPL-3.0-or-later
class_name NoteModuleEmbedBlock
extends PanelContainer

signal live_activation_requested(block: NoteModuleEmbedBlock)

const STAGE_MIN_HEIGHT: float = 520.0
const PRESENTATION_FULL: String = "full"
const PRESENTATION_COMPACT: String = "compact"
const PRESENTATION_CONTENT_ONLY: String = "content_only"
const CONTENT_ONLY_MAX_WIDTH_PX: float = 420.0
const CONTENT_ONLY_MAX_HEIGHT_PX: float = 250.0
const COMPACT_MAX_WIDTH_PX: float = 760.0
const COMPACT_MAX_HEIGHT_PX: float = 440.0

var _registry: ModuleRegistry
var _module_id: String = ""
var _caption: String = ""
var _instance_id: String = ""
var _info: Dictionary = {}
var _surface_host: ModuleSurfaceHost = ModuleSurfaceHost.new()
var _state_host: ModuleEphemeralStateHost
var _context: ModuleInstanceContext
var _surface: Control
var _title_label: Label
var _meta_label: Label
var _status_label: Label
var _stage_panel: PanelContainer
var _stage_host: Control
var _start_button: Button
var _reset_button: Button
var _stop_button: Button
var _live: bool = false


func _ready() -> void:
	theme_type_variation = "NoteResourceEmbedPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_ui()
	NotLightL10n.connect_locale_changed(_on_locale_changed)
	_refresh()


func _exit_tree() -> void:
	deactivate_live()
	_disconnect_registry()
	NotLightL10n.disconnect_locale_changed(_on_locale_changed)


func configure(
	registry: ModuleRegistry,
	module_id: String,
	caption: String,
	instance_id: String
) -> void:
	_disconnect_registry()
	deactivate_live()
	_registry = registry
	_module_id = module_id.strip_edges().to_lower()
	_caption = caption.strip_edges().left(NoteModuleEmbed.MAX_CAPTION_LENGTH)
	_instance_id = instance_id.strip_edges()
	if _registry != null and not _registry.modules_changed.is_connected(_on_modules_changed):
		_registry.modules_changed.connect(_on_modules_changed)
	if _title_label != null:
		_refresh()


func is_live() -> bool:
	return _live


func get_module_id() -> String:
	return _module_id


func activate_live() -> bool:
	if _live:
		return true
	if not _runtime_available():
		_refresh()
		return false
	var state_schema_version: int = _registry.get_state_schema_version(_module_id)
	if state_schema_version <= 0:
		_set_status(NotLightL10n.text("notes.module_embed.failed", {"error": "state_schema_version"}), true)
		return false
	var state_host: ModuleEphemeralStateHost = ModuleEphemeralStateHost.new()
	state_host.configure_ephemeral(
		_module_id,
		_instance_id,
		_registry.default_state(_module_id),
		state_schema_version
	)
	var materialized: Dictionary = _surface_host.materialize(_stage_host, _module_id, state_host, _registry)
	if not bool(materialized.get("ok", false)):
		state_host.detach()
		_set_status(NotLightL10n.text("notes.module_embed.failed", {"error": str(materialized.get("error", "unknown"))}), true)
		return false
	_state_host = state_host
	_surface = materialized.get("surface") as Control
	_context = materialized.get("context") as ModuleInstanceContext
	_live = true
	_stage_panel.visible = true
	_start_button.visible = false
	_reset_button.visible = true
	_stop_button.visible = true
	_push_presentation()
	if _context != null:
		_context.push_host_theme()
		_context.push_host_locale()
	_set_status(NotLightL10n.text("notes.module_embed.ephemeral"), false)
	return true


func deactivate_live() -> void:
	if _surface != null and is_instance_valid(_surface):
		if _stage_host != null and _surface.get_parent() == _stage_host:
			_stage_host.remove_child(_surface)
		_surface.queue_free()
	_surface = null
	_context = null
	if _state_host != null:
		_state_host.detach()
	_state_host = null
	_live = false
	if _stage_panel != null:
		_stage_panel.visible = false
	if _start_button != null:
		_start_button.visible = true
	if _reset_button != null:
		_reset_button.visible = false
	if _stop_button != null:
		_stop_button.visible = false


func reset_live() -> bool:
	if not _live:
		return false
	deactivate_live()
	return activate_live()


func _build_ui() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)
	var heading: VBoxContainer = VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 2)
	header.add_child(heading)
	_title_label = Label.new()
	_title_label.theme_type_variation = "BodyStrongLabel"
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_child(_title_label)
	_meta_label = Label.new()
	_meta_label.theme_type_variation = "CaptionLabel"
	_meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(_meta_label)
	var badge: Label = Label.new()
	NotLightL10n.bind_text(badge, "notes.module_embed.badge")
	badge.theme_type_variation = "SettingsValueLabel"
	badge.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
	header.add_child(badge)

	_stage_panel = PanelContainer.new()
	_stage_panel.theme_type_variation = "NoteEmbeddedMediaFrame"
	_stage_panel.custom_minimum_size = Vector2(0.0, STAGE_MIN_HEIGHT)
	_stage_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_panel.clip_contents = true
	_stage_panel.visible = false
	root.add_child(_stage_panel)
	_stage_host = Control.new()
	_stage_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage_host.clip_contents = true
	_stage_host.resized.connect(_push_presentation)
	_stage_panel.add_child(_stage_host)

	var controls: HBoxContainer = HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	root.add_child(controls)
	_start_button = Button.new()
	_start_button.theme_type_variation = "PrimaryButton"
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.custom_minimum_size = Vector2(150.0, 36.0)
	_start_button.pressed.connect(_on_start_pressed)
	controls.add_child(_start_button)
	_reset_button = Button.new()
	_reset_button.theme_type_variation = "GhostButton"
	_reset_button.custom_minimum_size = Vector2(110.0, 36.0)
	_reset_button.visible = false
	_reset_button.pressed.connect(_on_reset_pressed)
	controls.add_child(_reset_button)
	_stop_button = Button.new()
	_stop_button.theme_type_variation = "GhostButton"
	_stop_button.custom_minimum_size = Vector2(110.0, 36.0)
	_stop_button.visible = false
	_stop_button.pressed.connect(deactivate_live)
	controls.add_child(_stop_button)

	_status_label = Label.new()
	_status_label.theme_type_variation = "CaptionLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)


func _refresh() -> void:
	if _title_label == null:
		return
	_info = _registry.get_known_module_info(_module_id) if _registry != null else {}
	var module_name: String = str(_info.get("name", _module_id)) if not _info.is_empty() else _module_id
	_title_label.text = _caption if not _caption.is_empty() else module_name
	if _info.is_empty():
		_meta_label.text = _module_id
		_start_button.disabled = true
		_set_status(NotLightL10n.text("notes.module_embed.missing", {"module": _module_id}), true)
	elif bool(_info.get("pending_remove", false)) or not bool(_info.get("active", false)) or _registry == null or not _registry.is_module_active(_module_id):
		_meta_label.text = NotLightL10n.text("ui.format.version_module") % [str(_info.get("version", "?")), _module_id]
		_start_button.disabled = true
		if _live:
			deactivate_live()
		_set_status(NotLightL10n.text("notes.module_embed.restart_required"), false)
	else:
		_meta_label.text = NotLightL10n.text("ui.format.version_module") % [str(_info.get("version", "?")), _module_id]
		_start_button.disabled = false
		if not _live:
			_set_status(NotLightL10n.text("notes.module_embed.ready"), false)
	NotLightL10n.bind_text(_start_button, "notes.module_embed.start")
	NotLightL10n.bind_text(_reset_button, "notes.module_embed.reset")
	NotLightL10n.bind_text(_stop_button, "notes.module_embed.stop")


func _runtime_available() -> bool:
	if _registry == null or not ModuleManifest.is_valid_module_id(_module_id):
		return false
	if _info.is_empty() or bool(_info.get("pending_remove", false)):
		return false
	return bool(_info.get("active", false)) and _registry.is_module_active(_module_id)


func _push_presentation() -> void:
	if _surface == null or not is_instance_valid(_surface) or not _surface.has_method("notlight_set_host_presentation"):
		return
	var screen_size: Vector2 = _stage_host.size if _stage_host != null else Vector2.ZERO
	_surface.call("notlight_set_host_presentation", {
		"mode": _presentation_mode(screen_size),
		"screen_width": screen_size.x,
		"screen_height": screen_size.y,
	})


func _presentation_mode(screen_size: Vector2) -> String:
	if screen_size.x < CONTENT_ONLY_MAX_WIDTH_PX or screen_size.y < CONTENT_ONLY_MAX_HEIGHT_PX:
		return PRESENTATION_CONTENT_ONLY
	if screen_size.x < COMPACT_MAX_WIDTH_PX or screen_size.y < COMPACT_MAX_HEIGHT_PX:
		return PRESENTATION_COMPACT
	return PRESENTATION_FULL


func _set_status(text: String, is_error: bool) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.visible = not text.is_empty()
	_status_label.remove_theme_color_override("font_color")
	_status_label.add_theme_color_override(
		"font_color",
		NotLightTheme.semantic_color("danger") if is_error else NotLightTheme.semantic_color("text_muted")
	)


func _on_start_pressed() -> void:
	if not _live:
		live_activation_requested.emit(self)


func _on_reset_pressed() -> void:
	reset_live()


func _on_modules_changed() -> void:
	_refresh()


func _on_locale_changed(_locale: String) -> void:
	_refresh()
	if _context != null:
		_context.push_host_locale()


func _disconnect_registry() -> void:
	if _registry != null and _registry.modules_changed.is_connected(_on_modules_changed):
		_registry.modules_changed.disconnect(_on_modules_changed)
