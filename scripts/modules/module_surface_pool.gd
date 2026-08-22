# SPDX-License-Identifier: GPL-3.0-or-later
class_name ModuleSurfacePool
extends Control

signal surface_error(message: String)

const DEFAULT_MAX_ACTIVE_SURFACES: int = 3
const OFFSCREEN_MARGIN_PX: float = 80.0
const DRAG_BORDER_PX: float = 16.0
const FRAME_WIDTH_PX: int = 2
const CLOSE_BUTTON_MIN_EXTENT_PX: float = 168.0
const PRESENTATION_FULL: String = "full"
const PRESENTATION_COMPACT: String = "compact"
const PRESENTATION_CONTENT_ONLY: String = "content_only"
const CONTENT_ONLY_MAX_WIDTH_PX: float = 420.0
const CONTENT_ONLY_MAX_HEIGHT_PX: float = 250.0
const COMPACT_MAX_WIDTH_PX: float = 760.0
const COMPACT_MAX_HEIGHT_PX: float = 440.0

var board_view: NativeBoardView
var session: BoardSession
var registry: ModuleRegistry
var max_active_surfaces: int = DEFAULT_MAX_ACTIVE_SURFACES
var _hosts: Dictionary = {}
var _activation_order: Array[int] = []
var _last_module_revision: int = -1
var _transform_sync_count: int = 0
var _layout_reflow_count: int = 0
var _surface_host: ModuleSurfaceHost = ModuleSurfaceHost.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_sync_all_host_geometry)
	NotLightL10n.connect_locale_changed(_on_locale_changed)


func _exit_tree() -> void:
	_disconnect_sources()
	close_all()
	NotLightL10n.disconnect_locale_changed(_on_locale_changed)


func configure(
	target_board_view: NativeBoardView,
	board_session: BoardSession,
	module_registry: ModuleRegistry,
	active_surface_budget: int = DEFAULT_MAX_ACTIVE_SURFACES
) -> void:
	# Release old materialization against the old board before replacing references.
	_disconnect_sources()
	close_all()
	board_view = target_board_view
	session = board_session
	registry = module_registry
	set_active_surface_budget(active_surface_budget)
	_transform_sync_count = 0
	_layout_reflow_count = 0
	if board_view != null and is_instance_valid(board_view):
		board_view.clear_module_surface_activity()
		if not board_view.view_transform_changed.is_connected(_on_board_view_transform_changed):
			board_view.view_transform_changed.connect(_on_board_view_transform_changed)
		if not board_view.item_rect_changed.is_connected(_on_board_view_rect_changed):
			board_view.item_rect_changed.connect(_on_board_view_rect_changed)
	if session != null and not session.runtime.runtime_changed.is_connected(_on_runtime_changed):
		session.runtime.runtime_changed.connect(_on_runtime_changed)
	_last_module_revision = session.runtime.model.module_revision if session != null else -1


func set_active_surface_budget(value: int) -> void:
	max_active_surfaces = clampi(value, AppSettingsStore.MIN_MODULE_SURFACES, AppSettingsStore.MAX_MODULE_SURFACES)
	while _activation_order.size() > max_active_surfaces:
		close_surface(_activation_order[0])


func active_count() -> int:
	return _hosts.size()



func get_developer_diagnostics_snapshot() -> Dictionary:
	return {
		"module_surface_transform_syncs": _transform_sync_count,
		"module_surface_layout_reflows": _layout_reflow_count,
		"module_surfaces_active": active_count(),
		"module_surfaces_budget": max_active_surfaces,
	}



func is_active(entity_id: int) -> bool:
	return _hosts.has(entity_id)


func activate(entity_id: int) -> bool:
	if session == null or board_view == null or registry == null:
		return false
	if not session.runtime.model.modules.contains(entity_id):
		return false
	if _hosts.has(entity_id):
		_touch_order(entity_id)
		var existing: Control = (_hosts[entity_id] as Dictionary).get("host") as Control
		if existing != null:
			existing.move_to_front()
		return true
	var module_id: String = session.runtime.model.modules.get_module_id(entity_id)
	if not registry.is_module_active(module_id):
		surface_error.emit(NotLightL10n.text("modules.board.missing", {"id": module_id}))
		return false
	while _activation_order.size() >= max_active_surfaces:
		close_surface(_activation_order[0])

	# A live module has two screen-space regions: the canonical content rectangle
	# and a small host-owned interaction border around it. The border is intentionally
	# MOUSE_FILTER_IGNORE, so pointer input falls through to NativeBoardView. Its
	# regular 12px hit tolerance then lets users select/move an active module without
	# fighting the module's own interactive surface.
	var host: Control = Control.new()
	host.name = "ModuleSurface_%s" % entity_id
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.clip_contents = false
	add_child(host)

	var content: Control = Control.new()
	content.name = "ContentHost"
	content.mouse_filter = Control.MOUSE_FILTER_STOP
	content.clip_contents = true
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = DRAG_BORDER_PX
	content.offset_top = DRAG_BORDER_PX
	content.offset_right = -DRAG_BORDER_PX
	content.offset_bottom = -DRAG_BORDER_PX
	host.add_child(content)

	# Materialization itself is board-independent. BoardModuleInstanceStateHost owns
	# canonical state/undo semantics while ModuleSurfaceHost owns the public SDK
	# context + surface attach sequence. This same boundary can later host modules
	# outside a board without teaching ModuleInstanceContext about BoardSession.
	var state_host: BoardModuleInstanceStateHost = BoardModuleInstanceStateHost.new()
	state_host.configure(module_id, entity_id, session)
	var materialized: Dictionary = _surface_host.materialize(content, module_id, state_host, registry)
	if not bool(materialized.get("ok", false)):
		host.queue_free()
		_emit_materialization_error(module_id, materialized)
		return false
	var surface: Control = materialized.get("surface") as Control
	var context: ModuleInstanceContext = materialized.get("context") as ModuleInstanceContext

	# The visible frame belongs to the host-owned drag gutter, not to the module.
	# This makes the interaction boundary discoverable: the module content remains
	# canonical-size inside, while the 12px ring around it falls through to
	# NativeBoardView and can be used to select/move the live ModuleObject.
	var frame: Panel = Panel.new()
	frame.name = "InteractionFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", _frame_style())
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(frame)

	var close_button: Button = Button.new()
	close_button.text = "×"
	NotLightL10n.bind_tooltip(close_button, "modules.board.close_live")
	close_button.theme_type_variation = &"IconButton"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.position = Vector2(DRAG_BORDER_PX + 8.0, DRAG_BORDER_PX + 8.0)
	close_button.size = Vector2(34.0, 34.0)
	close_button.pressed.connect(close_surface.bind(entity_id))
	host.add_child(close_button)

	_hosts[entity_id] = {
		"host": host,
		"content": content,
		"frame": frame,
		"surface": surface,
		"context": context,
		"state_host": state_host,
		"close_button": close_button,
		"presentation": "",
		"revision": session.runtime.model.modules.get_revision(entity_id),
		"layout_zoom": -1.0,
		"bounds_size": Vector2.ZERO,
	}
	_activation_order.append(entity_id)
	# Hide the retained placeholder/card only after the live surface has been fully
	# attached. NativeBoardView queues a redraw so cached custom drawing disappears.
	board_view.set_module_surface_active(entity_id, true)
	_update_host_geometry(entity_id, _hosts[entity_id] as Dictionary)
	return true


func _emit_materialization_error(module_id: String, result: Dictionary) -> void:
	var code: String = str(result.get("error_code", ""))
	var detail: String = str(result.get("error", "")).strip_edges()
	match code:
		ModuleSurfaceHost.ERROR_INACTIVE:
			surface_error.emit(NotLightL10n.text("modules.board.missing", {"id": module_id}))
		ModuleSurfaceHost.ERROR_SURFACE_INVALID:
			surface_error.emit(NotLightL10n.text("modules.board.surface_invalid"))
		_:
			surface_error.emit(NotLightL10n.text("modules.board.state_invalid", {
				"id": module_id,
				"error": detail if not detail.is_empty() else code,
			}))


func close_surface(entity_id: int) -> void:
	if not _hosts.has(entity_id):
		return
	var record: Dictionary = _hosts[entity_id] as Dictionary
	var host: Control = record.get("host") as Control
	_hosts.erase(entity_id)
	_activation_order.erase(entity_id)
	# Hide the live Control synchronously before restoring retained rendering so the
	# two representations can never overlap for a frame.
	if host != null:
		host.visible = false
	if board_view != null and is_instance_valid(board_view):
		board_view.set_module_surface_active(entity_id, false)
	if host != null:
		host.queue_free()


func close_all() -> void:
	var ids: Array = _hosts.keys()
	for raw_id: Variant in ids:
		close_surface(int(raw_id))
	_hosts.clear()
	_activation_order.clear()
	if board_view != null and is_instance_valid(board_view):
		board_view.clear_module_surface_activity()


func _update_host_geometry(entity_id: int, record: Dictionary) -> void:
	var host: Control = record.get("host") as Control
	if host == null or board_view == null or session == null:
		return
	_transform_sync_count += 1
	var bounds: Rect2 = session.runtime.model.get_entity_bounds(entity_id)
	if not bounds.has_area():
		host.visible = false
		return

	# Modules can contain deep Control trees or their own SubViewports. Resizing that
	# hierarchy for every eased camera tick is unnecessary: retain a quantized
	# logical resolution and let CanvasItem scaling carry intermediate zoom frames.
	var screen_rect: Rect2 = BoardLiveSurfaceProjection.projected_rect(board_view, bounds)
	var viewport_rect: Rect2 = Rect2(Vector2.ZERO, size).grow(OFFSCREEN_MARGIN_PX)
	var projected_host_rect: Rect2 = screen_rect.grow(DRAG_BORDER_PX)
	host.visible = viewport_rect.intersects(projected_host_rect)
	if not host.visible:
		return

	var view_zoom: float = maxf(board_view.zoom, 0.01)
	var layout_zoom: float = BoardLiveSurfaceProjection.layout_zoom_for(view_zoom)
	var transform_scale: float = BoardLiveSurfaceProjection.transform_scale_for(view_zoom, layout_zoom)
	var previous_layout_zoom: float = float(record.get("layout_zoom", -1.0))
	var previous_bounds_size: Vector2 = record.get("bounds_size", Vector2.ZERO) as Vector2
	if not is_equal_approx(previous_layout_zoom, layout_zoom) or not previous_bounds_size.is_equal_approx(bounds.size):
		_layout_reflow_count += 1
		record["layout_zoom"] = layout_zoom
		record["bounds_size"] = bounds.size
		var logical_content_size: Vector2 = bounds.size * layout_zoom
		host.size = Vector2(
			maxf(1.0, logical_content_size.x + DRAG_BORDER_PX * 2.0),
			maxf(1.0, logical_content_size.y + DRAG_BORDER_PX * 2.0)
		)
		host.pivot_offset = Vector2.ZERO

	host.scale = Vector2.ONE * transform_scale
	host.position = screen_rect.position - Vector2.ONE * DRAG_BORDER_PX * transform_scale

	var close_button: Button = record.get("close_button") as Button
	if close_button != null:
		close_button.visible = (
			minf(screen_rect.size.x, screen_rect.size.y) >= CLOSE_BUTTON_MIN_EXTENT_PX
			and _presentation_mode(screen_rect.size) != PRESENTATION_CONTENT_ONLY
		)
	_push_presentation_if_changed(record, screen_rect.size)


func _presentation_mode(screen_size: Vector2) -> String:
	if screen_size.x < CONTENT_ONLY_MAX_WIDTH_PX or screen_size.y < CONTENT_ONLY_MAX_HEIGHT_PX:
		return PRESENTATION_CONTENT_ONLY
	if screen_size.x < COMPACT_MAX_WIDTH_PX or screen_size.y < COMPACT_MAX_HEIGHT_PX:
		return PRESENTATION_COMPACT
	return PRESENTATION_FULL


func _push_presentation_if_changed(record: Dictionary, screen_size: Vector2) -> void:
	var mode: String = _presentation_mode(screen_size)
	if str(record.get("presentation", "")) == mode:
		return
	record["presentation"] = mode
	var surface: Control = record.get("surface") as Control
	if surface == null or not surface.has_method("notlight_set_host_presentation"):
		return
	surface.call("notlight_set_host_presentation", {
		"mode": mode,
		"screen_width": screen_size.x,
		"screen_height": screen_size.y,
	})


func _on_board_view_transform_changed() -> void:
	# Camera movement drives retained content through BoardWorld immediately. Live
	# module Controls are children of NativeBoardView, but they are screen-space UI,
	# so synchronize their projected rect in the same transform notification.
	_sync_all_host_geometry()


func _on_board_view_rect_changed() -> void:
	_sync_all_host_geometry()


func _on_runtime_changed() -> void:
	if session == null:
		return
	var current_module_revision: int = session.runtime.model.module_revision
	var module_data_changed: bool = current_module_revision != _last_module_revision
	var ids: Array = _hosts.keys()
	for raw_id: Variant in ids:
		var entity_id: int = int(raw_id)
		if not session.runtime.model.contains(entity_id) or not session.runtime.model.modules.contains(entity_id):
			close_surface(entity_id)
			continue
		var record: Dictionary = _hosts[entity_id] as Dictionary
		_update_host_geometry(entity_id, record)
		if not module_data_changed:
			continue
		var revision: int = session.runtime.model.modules.get_revision(entity_id)
		if revision == int(record.get("revision", -1)):
			continue
		record["revision"] = revision
		var surface: Control = record.get("surface") as Control
		var context: ModuleInstanceContext = record.get("context") as ModuleInstanceContext
		var state: Dictionary = session.runtime.model.modules.get_state(entity_id)
		if surface != null and surface.has_method("notlight_set_host_state"):
			surface.call("notlight_set_host_state", state.duplicate(true))
		if context != null:
			context.push_host_state(state)
	_last_module_revision = current_module_revision


func _sync_all_host_geometry() -> void:
	if session == null or board_view == null:
		return
	var ids: Array = _hosts.keys()
	for raw_id: Variant in ids:
		var entity_id: int = int(raw_id)
		if not session.runtime.model.contains(entity_id):
			continue
		_update_host_geometry(entity_id, _hosts[entity_id] as Dictionary)


func _disconnect_sources() -> void:
	if board_view != null and is_instance_valid(board_view):
		if board_view.view_transform_changed.is_connected(_on_board_view_transform_changed):
			board_view.view_transform_changed.disconnect(_on_board_view_transform_changed)
		if board_view.item_rect_changed.is_connected(_on_board_view_rect_changed):
			board_view.item_rect_changed.disconnect(_on_board_view_rect_changed)
	if session != null and session.runtime.runtime_changed.is_connected(_on_runtime_changed):
		session.runtime.runtime_changed.disconnect(_on_runtime_changed)


func _touch_order(entity_id: int) -> void:
	_activation_order.erase(entity_id)
	_activation_order.append(entity_id)


func _on_locale_changed(_locale: String) -> void:
	for raw_record: Variant in _hosts.values():
		if raw_record is not Dictionary:
			continue
		var record: Dictionary = raw_record as Dictionary
		var context: ModuleInstanceContext = record.get("context") as ModuleInstanceContext
		if context != null:
			context.push_host_locale()


func push_theme_changed() -> void:
	for raw_record: Variant in _hosts.values():
		if raw_record is not Dictionary:
			continue
		var record: Dictionary = raw_record as Dictionary
		var frame: Panel = record.get("frame") as Panel
		if frame != null:
			frame.add_theme_stylebox_override("panel", _frame_style())
		var context: ModuleInstanceContext = record.get("context") as ModuleInstanceContext
		if context != null:
			context.push_host_theme()


func _frame_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	# The host frame must never paint beneath a transparent module surface. A
	# StyleBoxFlat shadow is rendered behind the whole box; with a transparent
	# center that shadow remains visible through the module and tints it darker.
	# Draw only the interaction border and let the module own every interior pixel.
	style.bg_color = Color.TRANSPARENT
	style.draw_center = false
	style.border_color = NotLightTheme.semantic_color("accent")
	style.set_border_width_all(FRAME_WIDTH_PX)
	style.set_corner_radius_all(14)
	style.shadow_size = 0
	return style
