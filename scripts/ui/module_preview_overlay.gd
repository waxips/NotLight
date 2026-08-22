# SPDX-License-Identifier: GPL-3.0-or-later
class_name ModulePreviewOverlay
extends Control

signal closed

const PRESENTATION_FULL: String = "full"
const PRESENTATION_COMPACT: String = "compact"
const PRESENTATION_CONTENT_ONLY: String = "content_only"
const CONTENT_ONLY_MAX_WIDTH_PX: float = 420.0
const CONTENT_ONLY_MAX_HEIGHT_PX: float = 250.0
const COMPACT_MAX_WIDTH_PX: float = 760.0
const COMPACT_MAX_HEIGHT_PX: float = 440.0

var registry: ModuleRegistry
var module_id: String = ""
var _info: Dictionary = {}
var _surface_host: ModuleSurfaceHost = ModuleSurfaceHost.new()
var _state_host: ModulePreviewStateHost
var _context: ModuleInstanceContext
var _surface: Control
var _title_label: Label
var _meta_label: Label
var _status_label: Label
var _stage_host: Control
var _reset_button: Button
var _previous_focus: Control


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_as_relative = false
	z_index = 1900
	_build_ui()
	NotLightL10n.connect_locale_changed(_on_locale_changed)


func _exit_tree() -> void:
	_stop_session()
	_disconnect_registry()
	NotLightL10n.disconnect_locale_changed(_on_locale_changed)


func configure(module_registry: ModuleRegistry) -> void:
	if registry == module_registry:
		return
	_disconnect_registry()
	_stop_session()
	registry = module_registry
	if registry != null and not registry.modules_changed.is_connected(_on_modules_changed):
		registry.modules_changed.connect(_on_modules_changed)


func open_module(new_module_id: String) -> void:
	var clean_id: String = new_module_id.strip_edges().to_lower()
	if registry == null or clean_id.is_empty():
		return
	var info: Dictionary = registry.get_known_module_info(clean_id)
	if info.is_empty():
		return
	_stop_session()
	module_id = clean_id
	_info = info.duplicate(true)
	_title_label.text = str(_info.get("name", module_id))
	_meta_label.text = NotLightL10n.text("ui.format.version_module") % [str(_info.get("version", "?")), module_id]
	_previous_focus = get_viewport().gui_get_focus_owner()
	visible = true
	move_to_front()
	grab_focus()
	_start_session()


func close_preview() -> void:
	if not visible:
		return
	_stop_session()
	module_id = ""
	_info = {}
	visible = false
	if _previous_focus != null and is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	_previous_focus = null
	closed.emit()


func _build_ui() -> void:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.035, 0.045, 0.040, 0.74)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	add_child(backdrop)

	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = "SettingsModalPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.055
	panel.anchor_top = 0.055
	panel.anchor_right = 0.945
	panel.anchor_bottom = 0.945
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0
	panel.custom_minimum_size = Vector2(720.0, 480.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)
	var title_box: VBoxContainer = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	header.add_child(title_box)
	_title_label = Label.new()
	_title_label.theme_type_variation = "TitleLabel"
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_box.add_child(_title_label)
	_meta_label = Label.new()
	_meta_label.theme_type_variation = "CaptionLabel"
	_meta_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_box.add_child(_meta_label)
	_reset_button = Button.new()
	NotLightL10n.bind_text(_reset_button, "modules.library.preview.reset")
	_reset_button.theme_type_variation = "GhostButton"
	_reset_button.custom_minimum_size = Vector2(110.0, 40.0)
	_reset_button.pressed.connect(_reset_session)
	header.add_child(_reset_button)
	var close_button: Button = Button.new()
	close_button.icon = load("res://assets/icons/close.svg") as Texture2D
	NotLightL10n.bind_tooltip(close_button, "library.preview.close")
	close_button.theme_type_variation = "IconButton"
	close_button.custom_minimum_size = Vector2(40.0, 40.0)
	close_button.pressed.connect(close_preview)
	header.add_child(close_button)

	var stage_panel: PanelContainer = PanelContainer.new()
	stage_panel.theme_type_variation = "SoftPanel"
	stage_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_panel.custom_minimum_size = Vector2(0.0, 360.0)
	root.add_child(stage_panel)
	_stage_host = Control.new()
	_stage_host.clip_contents = true
	_stage_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage_host.resized.connect(_push_presentation)
	stage_panel.add_child(_stage_host)

	_status_label = Label.new()
	_status_label.theme_type_variation = "CaptionLabel"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)


func _start_session() -> void:
	if registry == null or module_id.is_empty() or _stage_host == null:
		_set_status(NotLightL10n.text("modules.library.preview.unavailable"), true)
		return
	if bool(_info.get("pending_remove", false)) or not bool(_info.get("active", false)) or not registry.is_module_active(module_id):
		_set_status(NotLightL10n.text("modules.library.preview.restart_required"), true)
		return
	var state_schema_version: int = registry.get_state_schema_version(module_id)
	if state_schema_version <= 0:
		_set_status(NotLightL10n.text("modules.library.preview.failed", {"error": "state_schema_version"}), true)
		return
	var state_host: ModulePreviewStateHost = ModulePreviewStateHost.new()
	state_host.configure(module_id, registry.default_state(module_id), state_schema_version)
	var materialized: Dictionary = _surface_host.materialize(_stage_host, module_id, state_host, registry)
	if not bool(materialized.get("ok", false)):
		state_host.detach()
		_set_status(NotLightL10n.text("modules.library.preview.failed", {"error": str(materialized.get("error", "unknown"))}), true)
		return
	_state_host = state_host
	_surface = materialized.get("surface") as Control
	_context = materialized.get("context") as ModuleInstanceContext
	_push_presentation()
	if _context != null:
		_context.push_host_theme()
		_context.push_host_locale()
	_set_status(NotLightL10n.text("modules.library.preview.ephemeral"), false)
	_reset_button.disabled = false


func _reset_session() -> void:
	if module_id.is_empty():
		return
	_stop_session()
	_start_session()


func _stop_session() -> void:
	if _surface != null and is_instance_valid(_surface):
		if _surface.get_parent() == _stage_host:
			_stage_host.remove_child(_surface)
		_surface.queue_free()
	_surface = null
	_context = null
	if _state_host != null:
		_state_host.detach()
	_state_host = null
	if _reset_button != null:
		_reset_button.disabled = true


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


func _on_modules_changed() -> void:
	if not visible or module_id.is_empty() or registry == null:
		return
	var info: Dictionary = registry.get_known_module_info(module_id)
	if info.is_empty() or bool(info.get("pending_remove", false)) or not bool(info.get("active", false)) or not registry.is_module_active(module_id):
		close_preview()
		return
	_info = info.duplicate(true)
	_title_label.text = str(_info.get("name", module_id))
	_meta_label.text = NotLightL10n.text("ui.format.version_module") % [str(_info.get("version", "?")), module_id]


func _on_locale_changed(_locale: String) -> void:
	NotLightL10n.refresh_tree(self)
	if visible and registry != null and not module_id.is_empty():
		var info: Dictionary = registry.get_known_module_info(module_id)
		if not info.is_empty():
			_info = info.duplicate(true)
			_title_label.text = str(_info.get("name", module_id))
			_meta_label.text = NotLightL10n.text("ui.format.version_module") % [str(_info.get("version", "?")), module_id]
	if _context != null:
		_context.push_host_locale()
	if visible and _surface != null:
		_set_status(NotLightL10n.text("modules.library.preview.ephemeral"), false)


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			close_preview()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or event is not InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		close_preview()
		get_viewport().set_input_as_handled()


func _disconnect_registry() -> void:
	if registry != null and registry.modules_changed.is_connected(_on_modules_changed):
		registry.modules_changed.disconnect(_on_modules_changed)
