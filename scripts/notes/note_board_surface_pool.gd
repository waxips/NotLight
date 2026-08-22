# SPDX-License-Identifier: GPL-3.0-or-later
class_name NoteBoardSurfacePool
extends Control

signal surface_error(message: String)
signal asset_preview_requested(asset_id: String)

const DEFAULT_MAX_ACTIVE_SURFACES: int = AppSettingsStore.DEFAULT_NOTE_WORKSPACE_SURFACES
const MIN_ACTIVE_SURFACES: int = AppSettingsStore.MIN_NOTE_WORKSPACE_SURFACES
const MAX_ACTIVE_SURFACES: int = AppSettingsStore.MAX_NOTE_WORKSPACE_SURFACES
const OFFSCREEN_MARGIN_PX: float = 80.0
const DRAG_BORDER_PX: float = 14.0
const FRAME_WIDTH_PX: int = 2
const CONTENT_ONLY_MAX_WIDTH_PX: float = 430.0
const CONTENT_ONLY_MAX_HEIGHT_PX: float = 270.0
const COMPACT_MAX_WIDTH_PX: float = 760.0
const COMPACT_MAX_HEIGHT_PX: float = 480.0

var board_view: NativeBoardView
var session: BoardSession
var repository: NoteRepository
var formula_service: FormulaRenderService
var app_settings: AppSettingsStore
var asset_library: AssetLibraryService
var image_cache: ImageAssetCache
var video_media: VideoMediaService
var audio_media: AudioMediaService
var pdf_media: PdfMediaService
var module_registry: ModuleRegistry
var max_active_surfaces: int = DEFAULT_MAX_ACTIVE_SURFACES
var _hosts: Dictionary = {}
var _activation_order: Array[int] = []
var _transform_sync_count: int = 0
var _layout_reflow_count: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_sync_all_host_geometry)


func _exit_tree() -> void:
	_disconnect_sources()
	close_all()


func configure(
	target_board_view: NativeBoardView,
	board_session: BoardSession,
	note_repository: NoteRepository,
	render_service: FormulaRenderService,
	settings: AppSettingsStore,
	library_service: AssetLibraryService = null,
	cache: ImageAssetCache = null,
	video_service: VideoMediaService = null,
	audio_service: AudioMediaService = null,
	pdf_service: PdfMediaService = null,
	module_registry_service: ModuleRegistry = null,
	active_surface_budget: int = DEFAULT_MAX_ACTIVE_SURFACES
) -> void:
	_disconnect_sources()
	close_all()
	board_view = target_board_view
	session = board_session
	repository = note_repository
	formula_service = render_service
	app_settings = settings
	asset_library = library_service
	image_cache = cache
	video_media = video_service
	audio_media = audio_service
	pdf_media = pdf_service
	module_registry = module_registry_service
	set_active_surface_budget(active_surface_budget)
	_transform_sync_count = 0
	_layout_reflow_count = 0
	if board_view != null and is_instance_valid(board_view):
		board_view.clear_note_surface_activity()
		if not board_view.view_transform_changed.is_connected(_on_board_view_transform_changed):
			board_view.view_transform_changed.connect(_on_board_view_transform_changed)
		if not board_view.item_rect_changed.is_connected(_on_board_view_rect_changed):
			board_view.item_rect_changed.connect(_on_board_view_rect_changed)
	if session != null and not session.runtime.runtime_changed.is_connected(_on_runtime_changed):
		session.runtime.runtime_changed.connect(_on_runtime_changed)


func set_active_surface_budget(value: int) -> void:
	max_active_surfaces = clampi(value, MIN_ACTIVE_SURFACES, MAX_ACTIVE_SURFACES)
	while _activation_order.size() > max_active_surfaces:
		close_surface(_activation_order[0])


func active_count() -> int:
	return _hosts.size()



func get_developer_diagnostics_snapshot() -> Dictionary:
	return {
		"note_surface_transform_syncs": _transform_sync_count,
		"note_surface_layout_reflows": _layout_reflow_count,
		"note_surfaces_active": active_count(),
		"note_surfaces_budget": max_active_surfaces,
	}



func is_active(entity_id: int) -> bool:
	return _hosts.has(entity_id)


func activate(entity_id: int) -> bool:
	if session == null or board_view == null or repository == null:
		return false
	if not session.runtime.model.note_portals.contains(entity_id):
		return false
	if session.runtime.model.note_portals.get_view_mode(entity_id) != NotePortalStore.VIEW_WORKSPACE:
		return false
	if _hosts.has(entity_id):
		_touch_order(entity_id)
		var existing: Control = (_hosts[entity_id] as Dictionary).get("host") as Control
		if existing != null:
			existing.move_to_front()
		return true
	while _activation_order.size() >= max_active_surfaces:
		close_surface(_activation_order[0])
	var host: Control = Control.new()
	host.name = "NoteWorkspaceSurface_%s" % entity_id
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.clip_contents = false
	add_child(host)
	var content: PanelContainer = PanelContainer.new()
	content.theme_type_variation = "NoteBoardWorkspacePanel"
	content.mouse_filter = Control.MOUSE_FILTER_STOP
	content.clip_contents = true
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = DRAG_BORDER_PX
	content.offset_top = DRAG_BORDER_PX
	content.offset_right = -DRAG_BORDER_PX
	content.offset_bottom = -DRAG_BORDER_PX
	host.add_child(content)
	var surface: NoteBoardWorkspaceSurface = NoteBoardWorkspaceSurface.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.surface_error.connect(func(message: String) -> void: surface_error.emit(message))
	surface.asset_preview_requested.connect(func(asset_id: String) -> void: asset_preview_requested.emit(asset_id))
	content.add_child(surface)
	var frame: Panel = Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", _frame_style())
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(frame)
	var close_button: Button = Button.new()
	close_button.icon = load("res://assets/icons/close.svg") as Texture2D
	close_button.theme_type_variation = "IconButton"
	close_button.custom_minimum_size = Vector2(34.0, 34.0)
	close_button.position = Vector2(DRAG_BORDER_PX + 6.0, DRAG_BORDER_PX + 6.0)
	NotLightL10n.bind_tooltip(close_button, "notes.workspace.sleep")
	close_button.pressed.connect(close_surface.bind(entity_id))
	host.add_child(close_button)
	surface.configure(repository, formula_service, app_settings, session, entity_id, asset_library, image_cache, video_media, audio_media, pdf_media, module_registry)
	_hosts[entity_id] = {
		"host": host,
		"content": content,
		"surface": surface,
		"frame": frame,
		"close_button": close_button,
		"presentation": "",
		"layout_zoom": -1.0,
		"bounds_size": Vector2.ZERO,
	}
	_activation_order.append(entity_id)
	board_view.set_note_surface_active(entity_id, true)
	_update_host_geometry(entity_id, _hosts[entity_id] as Dictionary)
	return true


func close_surface(entity_id: int) -> void:
	if not _hosts.has(entity_id):
		return
	var record: Dictionary = _hosts[entity_id] as Dictionary
	var host: Control = record.get("host") as Control
	_hosts.erase(entity_id)
	_activation_order.erase(entity_id)
	if host != null:
		host.visible = false
	if board_view != null and is_instance_valid(board_view):
		board_view.set_note_surface_active(entity_id, false)
	if host != null:
		host.queue_free()


func close_all() -> void:
	var ids: Array = _hosts.keys()
	for raw_id: Variant in ids:
		close_surface(int(raw_id))
	_hosts.clear()
	_activation_order.clear()
	if board_view != null and is_instance_valid(board_view):
		board_view.clear_note_surface_activity()


func _update_host_geometry(entity_id: int, record: Dictionary) -> void:
	var host: Control = record.get("host") as Control
	if host == null or board_view == null or session == null:
		return
	_transform_sync_count += 1
	var bounds: Rect2 = session.runtime.model.get_entity_bounds(entity_id)
	if not bounds.has_area():
		host.visible = false
		return

	# Keep the expensive nested Notes UI at a quantized logical resolution. Camera
	# interpolation now changes only the host's CanvasItem transform between zoom
	# buckets instead of recursively resizing Tree/CodeEdit/RichText/Containers on
	# every eased zoom frame.
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
		close_button.visible = screen_rect.size.x >= 280.0 and screen_rect.size.y >= 180.0
	_push_presentation_if_changed(record, screen_rect.size)


func _presentation_mode(screen_size: Vector2) -> String:
	if screen_size.x < CONTENT_ONLY_MAX_WIDTH_PX or screen_size.y < CONTENT_ONLY_MAX_HEIGHT_PX:
		return "content_only"
	if screen_size.x < COMPACT_MAX_WIDTH_PX or screen_size.y < COMPACT_MAX_HEIGHT_PX:
		return "compact"
	return "full"


func _push_presentation_if_changed(record: Dictionary, screen_size: Vector2) -> void:
	var mode: String = _presentation_mode(screen_size)
	if str(record.get("presentation", "")) == mode:
		return
	record["presentation"] = mode
	var surface: NoteBoardWorkspaceSurface = record.get("surface") as NoteBoardWorkspaceSurface
	if surface != null:
		surface.notlight_set_host_presentation({
			"mode": mode,
			"screen_width": screen_size.x,
			"screen_height": screen_size.y,
		})


func _on_board_view_transform_changed() -> void:
	_sync_all_host_geometry()


func _on_board_view_rect_changed() -> void:
	_sync_all_host_geometry()


func _on_runtime_changed() -> void:
	if session == null:
		return
	var ids: Array = _hosts.keys()
	for raw_id: Variant in ids:
		var entity_id: int = int(raw_id)
		if (
			not session.runtime.model.contains(entity_id)
			or not session.runtime.model.note_portals.contains(entity_id)
			or session.runtime.model.note_portals.get_view_mode(entity_id) != NotePortalStore.VIEW_WORKSPACE
		):
			close_surface(entity_id)
			continue
		_update_host_geometry(entity_id, _hosts[entity_id] as Dictionary)


func _sync_all_host_geometry() -> void:
	if session == null or board_view == null:
		return
	for raw_id: Variant in _hosts.keys():
		var entity_id: int = int(raw_id)
		if session.runtime.model.contains(entity_id):
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


func push_theme_changed() -> void:
	for raw_record: Variant in _hosts.values():
		if raw_record is not Dictionary:
			continue
		var record: Dictionary = raw_record as Dictionary
		var frame: Panel = record.get("frame") as Panel
		if frame != null:
			frame.add_theme_stylebox_override("panel", _frame_style())


func _frame_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.draw_center = false
	style.border_color = NotLightTheme.semantic_color("accent")
	style.set_border_width_all(FRAME_WIDTH_PX)
	style.set_corner_radius_all(14)
	style.shadow_size = 0
	return style
