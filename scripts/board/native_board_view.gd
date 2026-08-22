# SPDX-License-Identifier: GPL-3.0-or-later
class_name NativeBoardView
extends Control

signal view_state_changed(view_state: Dictionary)
signal zoom_changed(zoom_value: float)
signal view_transform_changed
signal first_interaction
signal input_mode_changed(input_mode: int)
signal text_editor_state_changed(entity_id: int)
signal text_editor_format_changed
signal context_anchor_changed(screen_rect: Rect2, should_show: bool)
signal video_open_requested(asset_id: String, entity_id: int)
signal audio_open_requested(asset_id: String, entity_id: int)
signal formula_create_requested(world_position: Vector2)
signal formula_edit_requested(entity_id: int)
signal module_open_requested(entity_id: int)
signal note_open_requested(note_id: String, entity_id: int)
signal interaction_activity

const MIN_ZOOM: float = 0.08
const MAX_ZOOM: float = 8.0
const MOUSE_ZOOM_STEP: float = 1.075
const TRACKPAD_WHEEL_PAN_PIXELS: float = 48.0
const POINTER_PAN_MULTIPLIER: float = 0.95
const GESTURE_PAN_MULTIPLIER: float = 0.82
const VIEW_SAVE_DEBOUNCE_SECONDS: float = 0.22
const CAMERA_POSITION_EPSILON_SQUARED: float = 0.000001
const CAMERA_ZOOM_EPSILON: float = 0.00001
const POINTER_DRAG_THRESHOLD: float = 4.0
const DEFAULT_TEXT_SIZE: Vector2 = Vector2(300.0, 48.0)
const MIN_TEXT_SIZE: Vector2 = Vector2(40.0, 28.0)
const MIN_IMAGE_SIZE: Vector2 = Vector2(32.0, 32.0)
const DEFAULT_IMAGE_MAX_EXTENT: float = 520.0
const DEFAULT_PDF_MAX_EXTENT: float = 620.0
const DEFAULT_VIDEO_MAX_EXTENT: float = 620.0
const DEFAULT_AUDIO_SIZE: Vector2 = Vector2(420.0, 128.0)
const DEFAULT_NOTE_PORTAL_SIZE: Vector2 = Vector2(420.0, 260.0)
const DEFAULT_NOTE_WORKSPACE_SIZE: Vector2 = Vector2(760.0, 480.0)
const MIN_NOTE_PORTAL_SIZE: Vector2 = Vector2(220.0, 140.0)
const INTERNAL_CLIPBOARD_MARKER: String = "notlight-board://clipboard-v1"
const HANDLE_SIZE: float = 10.0
const HANDLE_HIT_SIZE: float = 18.0
const CONNECTOR_EDIT_HANDLE_RADIUS: float = 7.0
const CONNECTOR_EDIT_HIT_RADIUS: float = 13.0
const CONNECTOR_ENDPOINT_SOURCE: int = 0
const CONNECTOR_ENDPOINT_TARGET: int = 1
const CONNECTOR_ENDPOINT_NONE: int = -1
const RENDER_REFRESH_TEXT: int = 1
const RENDER_REFRESH_STROKE: int = 2
const RENDER_REFRESH_CONNECTOR: int = 4
const RENDER_REFRESH_IMAGE: int = 8
const RENDER_REFRESH_VIDEO: int = 16
const RENDER_REFRESH_AUDIO: int = 32
const RENDER_REFRESH_PDF: int = 64
const RENDER_REFRESH_FORMULA: int = 128
const RENDER_REFRESH_NOTE_PORTAL: int = 256
const RENDER_REFRESH_ALL: int = 511
const MAX_RENDER_REBUILDS_WHILE_MOVING: int = 1
const MAX_RENDER_REBUILDS_PER_FRAME: int = 1
const MOVING_RENDER_BUDGET_USEC: int = 1800
const IDLE_RENDER_BUDGET_USEC: int = 5200
const VIEW_RENDER_DEBOUNCE_SECONDS: float = 0.32
const COVERAGE_RETENTION_AREA_RATIO: float = 2.20
const CONTEXT_UI_RESTORE_DELAY_SECONDS: float = 0.10
const ZOOM_BUCKET_BASE: float = 1.32
const ZOOM_BUCKET_HYSTERESIS: float = 0.08
const STROKE_FULL_ENTER_ZOOM: float = 0.98
const STROKE_FULL_LEAVE_ZOOM: float = 0.90

const ACTION_NONE: int = 0
const ACTION_MOVE: int = 1
const ACTION_RESIZE: int = 2
const ACTION_MARQUEE: int = 3
const ACTION_CREATE_TEXT: int = 4
const ACTION_CONNECT: int = 5
const ACTION_REWIRE_CONNECTOR: int = 6
const ACTION_MOVE_ROUTER_POINT: int = 7
const ACTION_DRAW_STROKE: int = 8
const ACTION_ERASE_STROKES: int = 9

const HANDLE_NONE: int = -1
const HANDLE_TOP_LEFT: int = 0
const HANDLE_TOP: int = 1
const HANDLE_TOP_RIGHT: int = 2
const HANDLE_RIGHT: int = 3
const HANDLE_BOTTOM_RIGHT: int = 4
const HANDLE_BOTTOM: int = 5
const HANDLE_BOTTOM_LEFT: int = 6
const HANDLE_LEFT: int = 7

var camera_position: Vector2 = Vector2.ZERO
var zoom: float = 1.0
var _target_camera_position: Vector2 = Vector2.ZERO
var _target_zoom: float = 1.0
var _is_pointer_panning: bool = false
var _has_interacted: bool = false
var _view_dirty: bool = false
var _view_render_dirty: bool = false
var _interaction_idle_seconds: float = 0.0
var _input_mode: AppSettingsStore.InputMode = AppSettingsStore.InputMode.TRACKPAD
var _camera_sensitivity: float = 1.0
var _zoom_sensitivity: float = 1.0
var _camera_speed: float = 9.5
var _full_note_card_render: bool = false
var _active_tool_id: StringName = BoardToolController.TOOL_SELECT
var _runtime: BoardRuntime
var _grid_renderer: BoardGridRenderer
var _world_root: Node2D
var _text_renderer: TextBlockBatchRenderer
var _image_renderer: ImageBatchRenderer
var _pdf_renderer: PdfBatchRenderer
var _formula_renderer: FormulaBatchRenderer
var _video_renderer: VideoBatchRenderer
var _audio_renderer: AudioBatchRenderer
var _note_portal_renderer: NotePortalBatchRenderer
var _stroke_renderer: StrokeBatchRenderer
var _stroke_handoff_renderer: StrokeHandoffRenderer
var _connector_renderer: ConnectorBatchRenderer
var _image_cache: ImageAssetCache
var _pdf_media: PdfMediaService
var _formula_render: FormulaRenderService
var _video_media: VideoMediaService
var _audio_media: AudioMediaService
var _module_registry: ModuleRegistry
var _note_repository: NoteRepository
var _telemetry: PerformanceTelemetryService
var _text_worker: TextBlockRenderWorker = TextBlockRenderWorker.new()
var _text_plan_pending: bool = false
var _expected_text_signature: String = ""
var _render_coverage_rect: Rect2 = Rect2()
var _render_lod: int = -1
var _render_model_revision: int = -1
var _render_editing_id: int = -1
var _connector_coverage_rect: Rect2 = Rect2()
var _connector_model_revision: int = -1
var _connector_render_zoom_bucket: int = -999
var _connector_render_lod: int = -1
var _image_coverage_rect: Rect2 = Rect2()
var _image_model_revision: int = -1
var _image_render_zoom_bucket: int = -999
var _pdf_coverage_rect: Rect2 = Rect2()
var _pdf_model_revision: int = -1
var _pdf_render_zoom_bucket: int = -999
var _formula_coverage_rect: Rect2 = Rect2()
var _formula_model_revision: int = -1
var _formula_render_zoom_bucket: int = -999
var _video_coverage_rect: Rect2 = Rect2()
var _video_model_revision: int = -1
var _video_render_zoom_bucket: int = -999
var _audio_coverage_rect: Rect2 = Rect2()
var _audio_model_revision: int = -1
var _audio_render_zoom_bucket: int = -999
var _note_portal_coverage_rect: Rect2 = Rect2()
var _note_portal_model_revision: int = -1
var _note_portal_render_zoom_bucket: int = -999
var _stroke_coverage_rect: Rect2 = Rect2()
var _stroke_model_revision: int = -1
var _stroke_render_zoom_bucket: int = -999
var _stroke_render_lod: int = -1
var _render_pending_mask: int = 0
var _render_force_mask: int = 0
var _render_model_pending_mask: int = 0
var _render_scheduler_cursor: int = 0
var _shared_visibility_coverage: Rect2 = Rect2()
var _shared_visibility_revision: int = -1
var _shared_text_candidates: PackedInt64Array = PackedInt64Array()
var _shared_image_candidates: PackedInt64Array = PackedInt64Array()
var _shared_pdf_candidates: PackedInt64Array = PackedInt64Array()
var _shared_formula_candidates: PackedInt64Array = PackedInt64Array()
var _shared_video_candidates: PackedInt64Array = PackedInt64Array()
var _shared_audio_candidates: PackedInt64Array = PackedInt64Array()
var _shared_note_portal_candidates: PackedInt64Array = PackedInt64Array()
var _shared_stroke_candidates: PackedInt64Array = PackedInt64Array()
var _shared_connector_candidates: PackedInt64Array = PackedInt64Array()
var _stable_lod_level: int = -1
var _stable_stroke_lod_level: int = -1
var _last_emitted_zoom_percent: int = -1
var _hover_entity_id: int = 0
var _pointer_action: int = ACTION_NONE
var _pointer_start_screen: Vector2 = Vector2.ZERO
var _pointer_start_world: Vector2 = Vector2.ZERO
var _pointer_current_screen: Vector2 = Vector2.ZERO
var _pointer_current_world: Vector2 = Vector2.ZERO
var _action_started: bool = false
var _action_entity_ids: PackedInt64Array = PackedInt64Array()
var _action_before_bounds: Array[Rect2] = []
var _action_before_rotations: PackedFloat32Array = PackedFloat32Array()
var _action_before_text_records: Array[Dictionary] = []
var _resize_handle: int = HANDLE_NONE
var _marquee_additive: bool = false
var _marquee_base_selection: PackedInt64Array = PackedInt64Array()
var _hidden_render_ids: Dictionary = {}
# Live module surfaces are real Controls layered above the retained board renderer.
# Keep their canonical cards out of _draw() while materialized to avoid duplicate
# chrome and stale cached draw commands during camera pan/zoom.
var _live_module_surface_ids: Dictionary = {}
var _live_note_surface_ids: Dictionary = {}
var _hidden_connector_ids: Dictionary = {}
var _text_commit_handoff_ids: Dictionary = {}
var _stroke_commit_handoff_ids: Dictionary = {}
var _unhide_text_after_plan: bool = false
var _include_hidden_in_text_plan: bool = false
var _text_editor: TextEdit
var _editor_caret_timer: Timer
var _editor_caret_visible: bool = true
var _font_registry: TextFontRegistry = TextFontRegistry.new()
var _editing_entity_id: int = 0
var _editing_initial_text: String = ""
var _editor_last_text: String = ""
var _editor_typing_style_flags: int = 0
var _editor_typing_color: Color = TextBlockStore.COLOR_TEXT
var _editor_typing_override_active: bool = false
var _editing_initial_record: Dictionary = {}
var _editing_initial_bounds: Rect2 = Rect2()
var _editor_text_mutation_guard: bool = false
var _editing_preview_bounds: Rect2 = Rect2()
var _editing_creation_command: CreateTextBlockCommand
var _editor_closing: bool = false
var _overlay_font: Font
var _context_ui_suppressed: bool = false
var _context_anchor_dirty: bool = true
var _context_signal_initialized: bool = false
var _last_context_anchor_rect: Rect2 = Rect2()
var _last_context_anchor_visible: bool = false
var _drawing_style_id: int = StrokeStore.STYLE_PEN
var _drawing_color: Color = Color("#245cff")
var _drawing_width: float = 4.0
var _drawing_spray_spread: float = 1.0
var _drawing_eraser_enabled: bool = false
var _drawing_eraser_radius: float = 18.0
var _active_stroke_points: PackedVector2Array = PackedVector2Array()
var _active_stroke_preview: PackedVector2Array = PackedVector2Array()
var _eraser_pending_ids: Dictionary = {}
var _eraser_last_world: Vector2 = Vector2.ZERO

var _connection_source_entity_id: int = 0
var _connection_source_anchor: int = ConnectorGeometry.ANCHOR_RIGHT
var _connection_target_entity_id: int = 0
var _connection_target_anchor: int = ConnectorGeometry.ANCHOR_LEFT
var _connector_edit_entity_id: int = 0
var _connector_edit_endpoint: int = CONNECTOR_ENDPOINT_NONE
var _connector_edit_router_index: int = -1
var _connector_edit_before_record: Dictionary = {}
var _connector_edit_preview_router_points: PackedVector2Array = PackedVector2Array()
var _connector_edit_candidate_entity_id: int = 0
var _connector_edit_candidate_anchor: int = ConnectorGeometry.ANCHOR_LEFT


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	_overlay_font = ThemeDB.get_fallback_font()
	_build_render_layers()
	_build_text_editor()
	_text_worker.start()
	resized.connect(_on_resized)
	_sync_camera_visuals()
	_emit_zoom_if_needed(true)
	set_process(false)


func _exit_tree() -> void:
	_text_worker.stop()


func _process(delta: float) -> void:
	_recover_pointer_pan_release()
	_interaction_idle_seconds += delta
	var response: float = 1.0 - exp(-_camera_speed * delta)
	var previous_camera: Vector2 = camera_position
	var previous_zoom: float = zoom
	camera_position = camera_position.lerp(_target_camera_position, response)
	var safe_zoom: float = maxf(zoom, MIN_ZOOM)
	var safe_target_zoom: float = maxf(_target_zoom, MIN_ZOOM)
	zoom = exp(lerpf(log(safe_zoom), log(safe_target_zoom), response))

	var camera_settled: bool = camera_position.distance_squared_to(_target_camera_position) <= CAMERA_POSITION_EPSILON_SQUARED
	var zoom_settled: bool = absf(zoom - _target_zoom) <= CAMERA_ZOOM_EPSILON
	if camera_settled:
		camera_position = _target_camera_position
	if zoom_settled:
		zoom = _target_zoom

	var changed: bool = not camera_position.is_equal_approx(previous_camera) or not is_equal_approx(zoom, previous_zoom)
	if changed:
		_sync_camera_visuals()
		_emit_zoom_if_needed(false)
		if _needs_overlay_redraw():
			queue_redraw()

	var fully_settled: bool = camera_settled and zoom_settled
	var view_moving: bool = not fully_settled or _is_pointer_panning
	if view_moving:
		# Keep BoardSession's autosave idle clock paused for the entire eased camera
		# motion, not just for raw wheel/pan events. A low camera smoothing speed can
		# otherwise leave enough time for a pending stroke save to start while the
		# viewport is still animating.
		interaction_activity.emit()
	var render_interaction_active: bool = (
		_is_pointer_panning
		or _pointer_action != ACTION_NONE
		or _interaction_idle_seconds < VIEW_RENDER_DEBOUNCE_SECONDS
	)
	# View-dependent retained work may resume after the raw input quiet window even
	# while the camera is finishing its eased interpolation. The render layers live
	# under BoardWorld and therefore already follow the camera transform; waiting for
	# the sub-pixel easing tail made newly exposed/model-dirty content look "lazy".
	# Autosave remains paused for the full eased motion via interaction_activity.
	_schedule_deferred_view_refresh_if_ready()
	_flush_render_refresh_queue(render_interaction_active)
	_poll_text_worker()
	if _editing_entity_id > 0:
		_update_text_editor_layout()

	if _view_dirty and fully_settled and not _is_pointer_panning and _interaction_idle_seconds >= VIEW_SAVE_DEBOUNCE_SECONDS:
		_emit_view_state()
	if (
		not _is_pointer_panning
		and _pointer_action == ACTION_NONE
		and _interaction_idle_seconds >= CONTEXT_UI_RESTORE_DELAY_SECONDS
	):
		# Context UI follows perceived input idle, not the camera's sub-pixel
		# exponential tail. Waiting for the exact camera epsilon can keep a selected
		# object's toolbar hidden for well over a second after a large pan/zoom.
		_set_context_ui_suppressed(false)
	_update_developer_view_gauges(view_moving)
	if (
		fully_settled
		and not _is_pointer_panning
		and not _view_dirty
		and not _view_render_dirty
		and not _context_ui_suppressed
		and not _text_plan_pending
		and _render_pending_mask == 0
	):
		set_process(false)


func configure_runtime(board_runtime: BoardRuntime) -> void:
	if _runtime != null:
		if _runtime.selection.selection_changed.is_connected(_on_selection_changed):
			_runtime.selection.selection_changed.disconnect(_on_selection_changed)
		if _runtime.runtime_changed.is_connected(_on_runtime_changed):
			_runtime.runtime_changed.disconnect(_on_runtime_changed)
	_runtime = board_runtime
	_render_coverage_rect = Rect2()
	_render_model_revision = -1
	_render_lod = -1
	_render_editing_id = -1
	_connector_coverage_rect = Rect2()
	_connector_model_revision = -1
	_connector_render_zoom_bucket = -999
	_connector_render_lod = -1
	_image_coverage_rect = Rect2()
	_image_model_revision = -1
	_image_render_zoom_bucket = -999
	_pdf_coverage_rect = Rect2()
	_pdf_model_revision = -1
	_pdf_render_zoom_bucket = -999
	_formula_coverage_rect = Rect2()
	_formula_model_revision = -1
	_formula_render_zoom_bucket = -999
	_video_coverage_rect = Rect2()
	_video_model_revision = -1
	_video_render_zoom_bucket = -999
	_audio_coverage_rect = Rect2()
	_audio_model_revision = -1
	_audio_render_zoom_bucket = -999
	_note_portal_coverage_rect = Rect2()
	_note_portal_model_revision = -1
	_note_portal_render_zoom_bucket = -999
	_stroke_coverage_rect = Rect2()
	_stroke_model_revision = -1
	_stroke_render_zoom_bucket = -999
	_stroke_render_lod = -1
	_render_pending_mask = 0
	_render_force_mask = 0
	_render_model_pending_mask = 0
	_render_scheduler_cursor = 0
	_text_commit_handoff_ids.clear()
	_stroke_commit_handoff_ids.clear()
	_hidden_render_ids.clear()
	_hidden_connector_ids.clear()
	_unhide_text_after_plan = false
	_include_hidden_in_text_plan = false
	_shared_visibility_coverage = Rect2()
	_shared_visibility_revision = -1
	_shared_text_candidates = PackedInt64Array()
	_shared_image_candidates = PackedInt64Array()
	_shared_pdf_candidates = PackedInt64Array()
	_shared_formula_candidates = PackedInt64Array()
	_shared_video_candidates = PackedInt64Array()
	_shared_audio_candidates = PackedInt64Array()
	_shared_note_portal_candidates = PackedInt64Array()
	_shared_stroke_candidates = PackedInt64Array()
	_shared_connector_candidates = PackedInt64Array()
	_stable_lod_level = -1
	_stable_stroke_lod_level = -1
	_view_render_dirty = false
	_context_ui_suppressed = false
	_context_anchor_dirty = true
	_context_signal_initialized = false
	_last_context_anchor_rect = Rect2()
	_last_context_anchor_visible = false
	if _stroke_renderer != null:
		_stroke_renderer.configure(_runtime, _telemetry)
		_stroke_renderer.set_hidden_entity_ids({})
		_stroke_renderer.set_handoff_watch_ids({})
	if _stroke_handoff_renderer != null:
		_stroke_handoff_renderer.configure(_runtime)
	if _connector_renderer != null:
		_connector_renderer.configure_telemetry(_telemetry)
		_connector_renderer.set_hidden_connector_ids({}, false)
	if _image_renderer != null:
		_image_renderer.set_hidden_entity_ids({})
	if _pdf_renderer != null:
		_pdf_renderer.set_hidden_entity_ids({})
	if _video_renderer != null:
		_video_renderer.set_hidden_entity_ids({})
	if _audio_renderer != null:
		_audio_renderer.set_hidden_entity_ids({})
	if _note_portal_renderer != null:
		_note_portal_renderer.set_hidden_entity_ids({})
	_sync_text_renderer_hidden_ids()
	if _runtime != null:
		if not _runtime.selection.selection_changed.is_connected(_on_selection_changed):
			_runtime.selection.selection_changed.connect(_on_selection_changed)
		if not _runtime.runtime_changed.is_connected(_on_runtime_changed):
			_runtime.runtime_changed.connect(_on_runtime_changed)
	_request_text_refresh(true)
	_request_image_refresh(true)
	_request_pdf_refresh(true)
	_request_formula_refresh(true)
	_request_video_refresh(true)
	_request_audio_refresh(true)
	_request_note_portal_refresh(true)
	_request_stroke_refresh(true)
	_request_connector_refresh(true)
	queue_redraw()
	_emit_context_anchor()


func configure_note_repository(note_repository: NoteRepository) -> void:
	if _note_repository != null:
		if _note_repository.note_changed.is_connected(_on_note_repository_visual_changed):
			_note_repository.note_changed.disconnect(_on_note_repository_visual_changed)
		if _note_repository.notes_changed.is_connected(_on_note_repository_notes_changed):
			_note_repository.notes_changed.disconnect(_on_note_repository_notes_changed)
	_note_repository = note_repository
	if _note_repository != null:
		if not _note_repository.note_changed.is_connected(_on_note_repository_visual_changed):
			_note_repository.note_changed.connect(_on_note_repository_visual_changed)
		if not _note_repository.notes_changed.is_connected(_on_note_repository_notes_changed):
			_note_repository.notes_changed.connect(_on_note_repository_notes_changed)
	_request_note_portal_refresh(true)


func configure_image_cache(cache: ImageAssetCache) -> void:
	if _image_cache != null and _image_cache.texture_ready.is_connected(_on_image_texture_ready):
		_image_cache.texture_ready.disconnect(_on_image_texture_ready)
	_image_cache = cache
	if _image_cache != null:
		if not _image_cache.texture_ready.is_connected(_on_image_texture_ready):
			_image_cache.texture_ready.connect(_on_image_texture_ready)
		if _runtime != null:
			_image_cache.set_memory_limit_megabytes(_runtime.render_policy.max_texture_memory_mb)
			_image_cache.set_upload_budget(_runtime.render_policy.max_image_uploads_per_frame)
	_request_image_refresh(true)


func configure_pdf_media(pdf_media: PdfMediaService) -> void:
	if _pdf_media != null:
		if _pdf_media.page_ready.is_connected(_on_pdf_page_ready):
			_pdf_media.page_ready.disconnect(_on_pdf_page_ready)
		if _pdf_media.page_failed.is_connected(_on_pdf_page_failed):
			_pdf_media.page_failed.disconnect(_on_pdf_page_failed)
	_pdf_media = pdf_media
	if _pdf_media != null:
		if not _pdf_media.page_ready.is_connected(_on_pdf_page_ready):
			_pdf_media.page_ready.connect(_on_pdf_page_ready)
		if not _pdf_media.page_failed.is_connected(_on_pdf_page_failed):
			_pdf_media.page_failed.connect(_on_pdf_page_failed)
		if _runtime != null:
			_pdf_media.set_upload_budget(_runtime.render_policy.max_pdf_uploads_per_frame)
	_request_pdf_refresh(true)


func configure_formula_render(service: FormulaRenderService) -> void:
	if _formula_render != null:
		if _formula_render.texture_ready.is_connected(_on_formula_texture_ready):
			_formula_render.texture_ready.disconnect(_on_formula_texture_ready)
		if _formula_render.render_failed.is_connected(_on_formula_render_failed):
			_formula_render.render_failed.disconnect(_on_formula_render_failed)
	_formula_render = service
	if _formula_render != null:
		if not _formula_render.texture_ready.is_connected(_on_formula_texture_ready):
			_formula_render.texture_ready.connect(_on_formula_texture_ready)
		if not _formula_render.render_failed.is_connected(_on_formula_render_failed):
			_formula_render.render_failed.connect(_on_formula_render_failed)
	_request_formula_refresh(true)


func configure_video_media(video_media: VideoMediaService) -> void:
	if _video_media != null and _video_media.thumbnail_ready.is_connected(_on_video_thumbnail_ready):
		_video_media.thumbnail_ready.disconnect(_on_video_thumbnail_ready)
	_video_media = video_media
	if _video_media != null and not _video_media.thumbnail_ready.is_connected(_on_video_thumbnail_ready):
		_video_media.thumbnail_ready.connect(_on_video_thumbnail_ready)
	_request_video_refresh(true)


func configure_audio_media(audio_media: AudioMediaService) -> void:
	if _audio_media != null and _audio_media.waveform_ready.is_connected(_on_audio_waveform_ready):
		_audio_media.waveform_ready.disconnect(_on_audio_waveform_ready)
	_audio_media = audio_media
	if _audio_media != null and not _audio_media.waveform_ready.is_connected(_on_audio_waveform_ready):
		_audio_media.waveform_ready.connect(_on_audio_waveform_ready)
	_request_audio_refresh(true)


func configure_module_registry(module_registry: ModuleRegistry) -> void:
	if _module_registry != null and _module_registry.modules_changed.is_connected(_on_module_registry_changed):
		_module_registry.modules_changed.disconnect(_on_module_registry_changed)
	_module_registry = module_registry
	if _module_registry != null and not _module_registry.modules_changed.is_connected(_on_module_registry_changed):
		_module_registry.modules_changed.connect(_on_module_registry_changed)
	queue_redraw()


func _on_module_registry_changed() -> void:
	queue_redraw()


func set_module_surface_active(entity_id: int, active: bool) -> void:
	if entity_id <= 0:
		return
	if active:
		_live_module_surface_ids[entity_id] = true
	else:
		_live_module_surface_ids.erase(entity_id)
	# Custom CanvasItem drawing is cached until queue_redraw(). Materializing or
	# releasing a live surface must invalidate the retained ModuleObject card now,
	# otherwise the old white placeholder can linger and appear to drift on pan.
	queue_redraw()


func clear_module_surface_activity() -> void:
	if _live_module_surface_ids.is_empty():
		return
	_live_module_surface_ids.clear()
	queue_redraw()


func set_note_surface_active(entity_id: int, active: bool) -> void:
	if entity_id <= 0:
		return
	if active:
		_live_note_surface_ids[entity_id] = true
	else:
		_live_note_surface_ids.erase(entity_id)
	if _note_portal_renderer != null:
		_note_portal_renderer.set_live_entity_ids(_live_note_surface_ids)
	queue_redraw()


func clear_note_surface_activity() -> void:
	if _live_note_surface_ids.is_empty():
		return
	_live_note_surface_ids.clear()
	if _note_portal_renderer != null:
		_note_portal_renderer.set_live_entity_ids(_live_note_surface_ids)
	queue_redraw()


func configure_telemetry(telemetry_service: PerformanceTelemetryService) -> void:
	_telemetry = telemetry_service
	if _stroke_renderer != null:
		_stroke_renderer.configure(_runtime, _telemetry)
	if _connector_renderer != null:
		_connector_renderer.configure_telemetry(_telemetry)



func set_drawing_brush(style_id: int, color: Color, width: float, spray_spread: float, eraser_enabled: bool, eraser_radius: float) -> void:
	_drawing_style_id = clampi(style_id, StrokeStore.STYLE_PEN, StrokeStore.STYLE_SPRAY)
	_drawing_color = color
	_drawing_width = clampf(width, StrokeStore.MIN_WIDTH, StrokeStore.editor_max_width_for_style(_drawing_style_id))
	_drawing_spray_spread = clampf(spray_spread, StrokeStore.MIN_SPRAY_SPREAD, StrokeStore.MAX_SPRAY_SPREAD)
	_drawing_eraser_enabled = eraser_enabled
	_drawing_eraser_radius = clampf(eraser_radius, 6.0, 56.0)
	if _active_tool_id == BoardToolController.TOOL_DRAW:
		mouse_default_cursor_shape = Control.CURSOR_CROSS
		queue_redraw()

func set_view_state(state: Dictionary) -> void:
	var camera_data: Dictionary = state.get("camera_position", {}) as Dictionary
	camera_position = Vector2(float(camera_data.get("x", 0.0)), float(camera_data.get("y", 0.0)))
	zoom = clampf(float(state.get("zoom", 1.0)), MIN_ZOOM, MAX_ZOOM)
	_target_camera_position = camera_position
	_target_zoom = zoom
	_view_dirty = false
	_view_render_dirty = false
	_interaction_idle_seconds = 0.0
	_sync_camera_visuals()
	_request_text_refresh(true)
	_request_image_refresh(true)
	_request_pdf_refresh(true)
	_request_formula_refresh(true)
	_request_video_refresh(true)
	_request_audio_refresh(true)
	_request_stroke_refresh(true)
	_request_connector_refresh(true)
	queue_redraw()
	_emit_zoom_if_needed(true)
	_emit_context_anchor(true)
	set_process(_text_plan_pending or _render_pending_mask != 0)


func get_view_state() -> Dictionary:
	return {
		"camera_position": {"x": _target_camera_position.x, "y": _target_camera_position.y},
		"zoom": _target_zoom,
	}


func flush_view_state() -> void:
	if _view_dirty:
		_emit_view_state()


func apply_settings(snapshot: Dictionary) -> void:
	var mode_value: int = int(snapshot.get("input_mode", int(AppSettingsStore.InputMode.TRACKPAD)))
	_input_mode = AppSettingsStore.InputMode.TRACKPAD if mode_value == int(AppSettingsStore.InputMode.TRACKPAD) else AppSettingsStore.InputMode.MOUSE
	_camera_sensitivity = clampf(float(snapshot.get("camera_sensitivity", 1.0)), 0.25, 3.0)
	_zoom_sensitivity = clampf(float(snapshot.get("zoom_sensitivity", 1.0)), 0.25, 3.0)
	_camera_speed = clampf(float(snapshot.get("camera_speed", 9.5)), 3.0, 30.0)
	var next_full_note_card_render: bool = bool(snapshot.get("effective_full_note_card_render", false))
	if _full_note_card_render != next_full_note_card_render:
		_full_note_card_render = next_full_note_card_render
		_request_note_portal_refresh(true)
	if _grid_renderer != null:
		_grid_renderer.set_intensity(int(snapshot.get("grid_intensity", int(AppSettingsStore.GridIntensity.BALANCED))))
	input_mode_changed.emit(int(_input_mode))


func set_active_tool(tool_id: StringName) -> void:
	_active_tool_id = tool_id
	if not _is_pointer_panning:
		mouse_default_cursor_shape = _default_cursor()
	_update_hover(get_local_mouse_position())


func set_zoom(new_zoom: float, anchor_screen: Vector2 = size * 0.5, immediate: bool = false) -> void:
	var clamped: float = clampf(new_zoom, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(clamped, _target_zoom):
		return
	var world_anchor: Vector2 = _target_camera_position + (anchor_screen - size * 0.5) / maxf(_target_zoom, 0.001)
	_target_zoom = clamped
	_target_camera_position = world_anchor - (anchor_screen - size * 0.5) / _target_zoom
	_set_context_ui_suppressed(true)
	if immediate:
		zoom = _target_zoom
		camera_position = _target_camera_position
		_sync_camera_visuals()
		_emit_zoom_if_needed(false)
		if _needs_overlay_redraw():
			queue_redraw()
	_mark_interaction()
	_mark_view_dirty()


func zoom_in() -> void:
	set_zoom(_target_zoom * pow(MOUSE_ZOOM_STEP, _zoom_sensitivity))


func zoom_out() -> void:
	set_zoom(_target_zoom / pow(MOUSE_ZOOM_STEP, _zoom_sensitivity))


func reset_view() -> void:
	if _target_camera_position.is_zero_approx() and is_equal_approx(_target_zoom, 1.0):
		return
	_set_context_ui_suppressed(true)
	_target_camera_position = Vector2.ZERO
	_target_zoom = 1.0
	_mark_interaction()
	_mark_view_dirty()


func screen_to_world(screen_position: Vector2) -> Vector2:
	return camera_position + (screen_position - size * 0.5) / maxf(zoom, 0.001)


func world_to_screen(world_position: Vector2) -> Vector2:
	return (world_position - camera_position) * zoom + size * 0.5


func get_visible_world_rect() -> Rect2:
	var world_size: Vector2 = size / maxf(zoom, 0.001)
	return Rect2(camera_position - world_size * 0.5, world_size)


func commit_active_editor() -> void:
	_commit_text_editor()


func edit_primary_text(select_all: bool = false) -> void:
	if _runtime == null:
		return
	var entity_id: int = _runtime.selection.primary_id
	if entity_id > 0 and _runtime.model.get_entity_type(entity_id) == BoardEntityTypes.TEXT:
		_open_text_editor(entity_id, select_all)


func is_text_editor_active() -> bool:
	return _editing_entity_id > 0


func get_editor_format_context() -> Dictionary:
	if _runtime == null or _editing_entity_id <= 0 or not _runtime.model.text_blocks.contains(_editing_entity_id):
		return {}
	var record: Dictionary = _runtime.model.text_blocks.get_record(_editing_entity_id)
	var character_range: Vector2i = _editor_character_range()
	var sample_offset: int = character_range.x
	if character_range.y > character_range.x:
		sample_offset = character_range.x
	elif sample_offset > 0:
		sample_offset -= 1
	var style: Dictionary = _runtime.model.text_blocks.get_style_at(_editing_entity_id, sample_offset)
	if character_range.x == character_range.y and _editor_typing_override_active:
		style = {"flags": _editor_typing_style_flags, "color": _editor_typing_color}
	var paragraph_index: int = TextBlockStore.paragraph_index_for_offset(_text_editor.text, character_range.x)
	return {
		"entity_id": _editing_entity_id,
		"font_size": float(record.get("font_size", TextBlockStore.DEFAULT_FONT_SIZE)),
		"font_family": str(record.get("font_family", TextBlockStore.DEFAULT_FONT_FAMILY)),
		"alignment": int(record.get("alignment", HORIZONTAL_ALIGNMENT_LEFT)),
		"style_flags": int(style.get("flags", int(record.get("base_style_flags", 0)))),
		"text_color": (style.get("color", TextBlockStore.COLOR_TEXT) as Color).to_html(true),
		"background_color": str(record.get("background_color", Color.TRANSPARENT.to_html(true))),
		"list_type": _runtime.model.text_blocks.get_paragraph_list_type(_editing_entity_id, paragraph_index),
		"has_selection": _text_editor.has_selection(),
	}


func apply_editor_font_size(font_size: float) -> void:
	if not _has_active_text_editor():
		return
	_runtime.model.text_blocks.set_font_size(_editing_entity_id, font_size)
	_refresh_active_editor_after_format(true)


func apply_editor_font_family(font_family: String) -> void:
	if not _has_active_text_editor():
		return
	_runtime.model.text_blocks.set_font_family(_editing_entity_id, font_family)
	_refresh_active_editor_after_format(true)


func apply_editor_alignment(alignment: HorizontalAlignment) -> void:
	if not _has_active_text_editor():
		return
	_runtime.model.text_blocks.set_alignment(_editing_entity_id, alignment)
	_refresh_active_editor_after_format(false)


func apply_editor_style_flag(flag: int, enabled: bool) -> void:
	if not _has_active_text_editor():
		return
	var character_range: Vector2i = _editor_character_range()
	if character_range.x == character_range.y:
		if not _editor_typing_override_active:
			_sync_editor_typing_style_from_caret(false)
		if enabled:
			_editor_typing_style_flags |= flag
		else:
			_editor_typing_style_flags &= ~flag
		_editor_typing_style_flags &= TextBlockStore.FONT_STYLE_ALL
		_editor_typing_override_active = true
		text_editor_format_changed.emit()
		return
	_runtime.model.text_blocks.apply_style_flag_range(_editing_entity_id, character_range.x, character_range.y, flag, enabled)
	_sync_editor_typing_style_from_caret(true)
	_refresh_active_editor_after_format(true)


func apply_editor_text_color(color: Color) -> void:
	if not _has_active_text_editor():
		return
	var character_range: Vector2i = _editor_character_range()
	if character_range.x == character_range.y:
		if not _editor_typing_override_active:
			_sync_editor_typing_style_from_caret(false)
		_editor_typing_color = color
		_editor_typing_override_active = true
		if _text_editor.text.is_empty():
			_runtime.model.text_blocks.set_colors(
				_editing_entity_id,
				_runtime.model.text_blocks.get_background_color(_editing_entity_id),
				color
			)
		text_editor_format_changed.emit()
		return
	_runtime.model.text_blocks.apply_text_color_range(_editing_entity_id, character_range.x, character_range.y, color)
	_sync_editor_typing_style_from_caret(true)
	_refresh_active_editor_after_format(false)


func apply_editor_background_color(color: Color) -> void:
	if not _has_active_text_editor():
		return
	_runtime.model.text_blocks.set_background_color(_editing_entity_id, color)
	_refresh_active_editor_after_format(true)


func apply_editor_background_opacity(opacity: float) -> void:
	if not _has_active_text_editor():
		return
	var background: Color = _runtime.model.text_blocks.get_background_color(_editing_entity_id)
	if background.a <= 0.001:
		background = Color("#eef6ed")
	background.a = clampf(opacity, 0.0, 1.0)
	_runtime.model.text_blocks.set_background_color(_editing_entity_id, background)
	_refresh_active_editor_after_format(true)


func apply_editor_list_type(list_type: int) -> void:
	if not _has_active_text_editor():
		return
	var character_range: Vector2i = _editor_character_range()
	var paragraph_indices: PackedInt32Array = TextLayoutUtils.paragraph_indices_for_character_range(_text_editor.text, character_range.x, character_range.y)
	_runtime.model.text_blocks.set_paragraph_list_type(_editing_entity_id, paragraph_indices, list_type)
	_refresh_active_editor_after_format(true)


func adjust_editor_list_indent(delta: int) -> void:
	if not _has_active_text_editor() or delta == 0:
		return
	var character_range: Vector2i = _editor_character_range()
	var paragraph_indices: PackedInt32Array = TextLayoutUtils.paragraph_indices_for_character_range(_text_editor.text, character_range.x, character_range.y)
	_runtime.model.text_blocks.adjust_paragraph_indent(_editing_entity_id, paragraph_indices, delta)
	_refresh_active_editor_after_format(true)


func delete_selection() -> void:
	if _runtime == null or _runtime.selection.size() == 0:
		return
	_commit_text_editor()
	var selected_ids: PackedInt64Array = _runtime.selection.get_selected_ids()
	var command: DeleteEntitiesCommand = DeleteEntitiesCommand.new(selected_ids)
	if _runtime.commands.execute(command, _runtime):
		_runtime.selection.clear()
		_request_text_refresh(true)


func select_all_text() -> void:
	if _runtime == null:
		return
	var ids: PackedInt64Array = _runtime.model.text_blocks.entity_ids.duplicate()
	_runtime.selection.set_many(ids, int(ids[ids.size() - 1]) if not ids.is_empty() else 0)


func copy_selection() -> bool:
	if _runtime == null or _runtime.selection.size() == 0:
		return false
	_commit_text_editor()
	var captured: bool = _runtime.clipboard.capture(_runtime, _runtime.selection.get_selected_ids())
	if captured:
		DisplayServer.clipboard_set(INTERNAL_CLIPBOARD_MARKER)
	return captured


func paste_clipboard() -> bool:
	if _runtime == null or not _runtime.clipboard.has_content():
		return false
	_commit_text_editor()
	var target_world: Vector2 = get_pointer_world_position()
	var command: PasteBoardObjectsCommand = _runtime.clipboard.make_paste_command_at(target_world)
	if command == null or not _runtime.commands.execute(command, _runtime):
		return false
	_runtime.selection.set_many(
		command.created_selectable_ids,
		int(command.created_selectable_ids[command.created_selectable_ids.size() - 1]) if not command.created_selectable_ids.is_empty() else 0
	)
	_request_text_refresh(true)
	_request_image_refresh(true)
	_request_connector_refresh(true)
	return true


func duplicate_selection() -> bool:
	if _runtime == null or _runtime.selection.size() == 0:
		return false
	_commit_text_editor()
	if not _runtime.clipboard.capture(_runtime, _runtime.selection.get_selected_ids()):
		return false
	return paste_clipboard()


func get_pointer_world_position() -> Vector2:
	return screen_to_world(get_local_mouse_position())


func get_view_center_world_position() -> Vector2:
	return camera_position


func paste_external_text(text: String, world_position: Vector2) -> bool:
	if _runtime == null or text.is_empty():
		return false
	_commit_text_editor()
	var record: Dictionary = {
		"text": text,
		"font_size": TextBlockStore.DEFAULT_FONT_SIZE,
		"font_family": TextBlockStore.DEFAULT_FONT_FAMILY,
		"layout_mode": TextBlockStore.LAYOUT_AUTO_WIDTH,
		"background_color": Color.TRANSPARENT.to_html(true),
		"text_color": TextBlockStore.COLOR_TEXT.to_html(true),
		"base_style_flags": 0,
		"paragraphs": [],
	}
	var initial_bounds: Rect2 = Rect2(world_position, DEFAULT_TEXT_SIZE)
	var fitted: Rect2 = TextLayoutUtils.fit_record_bounds(initial_bounds, record, MIN_TEXT_SIZE)
	fitted.position = world_position - fitted.size * 0.5
	var command: CreateTextBlockCommand = CreateTextBlockCommand.new(
		fitted,
		text,
		TextBlockStore.DEFAULT_FONT_SIZE,
		HORIZONTAL_ALIGNMENT_LEFT,
		TextBlockStore.STYLE_PLAIN,
		TextBlockStore.LAYOUT_AUTO_WIDTH,
		Color.TRANSPARENT,
		TextBlockStore.COLOR_TEXT,
		_runtime.model.get_max_z_order() + 1
	)
	if not _runtime.commands.execute(command, _runtime):
		return false
	_runtime.selection.set_single(command.created_entity_id)
	_mark_interaction()
	_request_text_refresh(true)
	queue_redraw()
	return true


func create_image_from_asset(asset_id: String, pixel_size: Vector2i, world_position: Vector2) -> int:
	if _runtime == null or asset_id.strip_edges().is_empty():
		return 0
	_commit_text_editor()
	var safe_pixels: Vector2 = Vector2(maxi(1, pixel_size.x), maxi(1, pixel_size.y))
	var scale_value: float = minf(1.0, DEFAULT_IMAGE_MAX_EXTENT / maxf(safe_pixels.x, safe_pixels.y))
	var board_size: Vector2 = safe_pixels * scale_value
	if maxf(board_size.x, board_size.y) < 96.0:
		board_size *= 96.0 / maxf(1.0, maxf(board_size.x, board_size.y))
	var bounds: Rect2 = Rect2(world_position - board_size * 0.5, board_size)
	var command: CreateImageCommand = CreateImageCommand.new(
		bounds,
		asset_id,
		pixel_size,
		_runtime.model.get_max_z_order() + 1
	)
	if not _runtime.commands.execute(command, _runtime):
		return 0
	_runtime.selection.set_single(command.created_entity_id)
	_mark_interaction()
	_request_image_refresh(true)
	queue_redraw()
	return command.created_entity_id


func create_pdf_from_asset(asset_id: String, page_count: int, page_size: Vector2i, world_position: Vector2) -> int:
	if _runtime == null or asset_id.strip_edges().is_empty():
		return 0
	_commit_text_editor()
	var safe_page_size: Vector2 = Vector2(maxi(1, page_size.x), maxi(1, page_size.y))
	var scale_value: float = minf(1.0, DEFAULT_PDF_MAX_EXTENT / maxf(safe_page_size.x, safe_page_size.y))
	var board_size: Vector2 = safe_page_size * scale_value
	if maxf(board_size.x, board_size.y) < 180.0:
		board_size *= 180.0 / maxf(1.0, maxf(board_size.x, board_size.y))
	var bounds: Rect2 = Rect2(world_position - board_size * 0.5, board_size)
	var command: CreatePdfCommand = CreatePdfCommand.new(
		bounds, asset_id, maxi(1, page_count), page_size, _runtime.model.get_max_z_order() + 1
	)
	if not _runtime.commands.execute(command, _runtime):
		return 0
	_runtime.selection.set_single(command.created_entity_id)
	_mark_interaction()
	_request_pdf_refresh(true)
	queue_redraw()
	return command.created_entity_id


func set_pdf_page(entity_id: int, page_index: int) -> bool:
	if _runtime == null or not _runtime.model.pdfs.contains(entity_id):
		return false
	var before_page: int = _runtime.model.pdfs.get_page_index(entity_id)
	var safe_page: int = clampi(page_index, 0, _runtime.model.pdfs.get_page_count(entity_id) - 1)
	if before_page == safe_page:
		return true
	var command: UpdatePdfPageCommand = UpdatePdfPageCommand.new(entity_id, before_page, safe_page)
	if not _runtime.commands.execute(command, _runtime):
		return false
	_request_pdf_refresh(true)
	queue_redraw()
	return true


func create_video_from_asset(
	asset_id: String,
	pixel_size: Vector2i,
	duration_seconds: float,
	world_position: Vector2
) -> int:
	if _runtime == null or asset_id.strip_edges().is_empty():
		return 0
	_commit_text_editor()
	var safe_pixels: Vector2 = Vector2(maxi(1, pixel_size.x), maxi(1, pixel_size.y))
	var scale_value: float = minf(1.0, DEFAULT_VIDEO_MAX_EXTENT / maxf(safe_pixels.x, safe_pixels.y))
	var board_size: Vector2 = safe_pixels * scale_value
	if maxf(board_size.x, board_size.y) < 140.0:
		board_size *= 140.0 / maxf(1.0, maxf(board_size.x, board_size.y))
	var bounds: Rect2 = Rect2(world_position - board_size * 0.5, board_size)
	var command: CreateVideoCommand = CreateVideoCommand.new(
		bounds,
		asset_id,
		pixel_size,
		duration_seconds,
		_runtime.model.get_max_z_order() + 1
	)
	if not _runtime.commands.execute(command, _runtime):
		return 0
	_runtime.selection.set_single(command.created_entity_id)
	_mark_interaction()
	_request_video_refresh(true)
	queue_redraw()
	return command.created_entity_id


func create_audio_from_asset(asset_id: String, duration_seconds: float, world_position: Vector2) -> int:
	if _runtime == null or asset_id.strip_edges().is_empty():
		return 0
	_commit_text_editor()
	var bounds: Rect2 = Rect2(world_position - DEFAULT_AUDIO_SIZE * 0.5, DEFAULT_AUDIO_SIZE)
	var command: CreateAudioCommand = CreateAudioCommand.new(
		bounds,
		asset_id,
		duration_seconds,
		_runtime.model.get_max_z_order() + 1
	)
	if not _runtime.commands.execute(command, _runtime):
		return 0
	_runtime.selection.set_single(command.created_entity_id)
	_mark_interaction()
	_request_audio_refresh(true)
	queue_redraw()
	return command.created_entity_id


func create_note_portal(
	note_id: String,
	world_position: Vector2,
	view_mode: int = NotePortalStore.VIEW_PREVIEW
) -> int:
	if _runtime == null or note_id.strip_edges().is_empty():
		return 0
	if _note_repository != null and not _note_repository.contains(note_id):
		return 0
	_commit_text_editor()
	var safe_mode: int = clampi(view_mode, NotePortalStore.VIEW_PREVIEW, NotePortalStore.VIEW_WORKSPACE)
	var portal_size: Vector2 = DEFAULT_NOTE_WORKSPACE_SIZE if safe_mode == NotePortalStore.VIEW_WORKSPACE else DEFAULT_NOTE_PORTAL_SIZE
	var bounds: Rect2 = Rect2(world_position - portal_size * 0.5, portal_size)
	var command: CreateNotePortalCommand = CreateNotePortalCommand.new(
		bounds,
		note_id,
		safe_mode,
		_runtime.model.get_max_z_order() + 1
	)
	if not _runtime.commands.execute(command, _runtime):
		return 0
	_runtime.selection.set_single(command.created_entity_id)
	_mark_interaction()
	_request_note_portal_refresh(true)
	queue_redraw()
	return command.created_entity_id


func focus_single_selection() -> bool:
	if _runtime == null or _runtime.selection.size() != 1:
		return false
	return focus_entity(_runtime.selection.primary_id, false)


func focus_entity(entity_id: int, select_entity: bool = true) -> bool:
	if _runtime == null or entity_id <= 0 or not _runtime.model.contains(entity_id):
		return false
	_commit_text_editor()
	if select_entity:
		_runtime.selection.set_single(entity_id)
	var bounds: Rect2 = _runtime.model.get_entity_bounds(entity_id)
	if not bounds.has_area():
		return false
	var minimum_world_extent: float = 36.0 / maxf(_target_zoom, MIN_ZOOM)
	var focus_size: Vector2 = Vector2(
		maxf(bounds.size.x, minimum_world_extent),
		maxf(bounds.size.y, minimum_world_extent)
	)
	var padded_size: Vector2 = focus_size * 1.22
	var available: Vector2 = Vector2(maxf(160.0, size.x - 180.0), maxf(140.0, size.y - 170.0))
	var fit_zoom: float = minf(available.x / maxf(padded_size.x, 1.0), available.y / maxf(padded_size.y, 1.0))
	_target_camera_position = bounds.get_center()
	_target_zoom = clampf(fit_zoom, MIN_ZOOM, MAX_ZOOM)
	_set_context_ui_suppressed(true)
	_mark_interaction()
	_mark_view_dirty()
	set_process(true)
	return true


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMagnifyGesture:
		var magnify_event: InputEventMagnifyGesture = event as InputEventMagnifyGesture
		var factor: float = maxf(magnify_event.factor, 0.01)
		set_zoom(_target_zoom * pow(factor, _zoom_sensitivity), magnify_event.position)
		accept_event()
		return
	if event is InputEventPanGesture:
		var pan_event: InputEventPanGesture = event as InputEventPanGesture
		_pan_by_screen_delta(pan_event.delta * GESTURE_PAN_MULTIPLIER * _camera_sensitivity)
		accept_event()
		return
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and _handle_wheel(mouse_event):
			accept_event()
			return
		var is_pan_button: bool = mouse_event.button_index == MOUSE_BUTTON_RIGHT or mouse_event.button_index == MOUSE_BUTTON_MIDDLE
		var is_hand_pan: bool = mouse_event.button_index == MOUSE_BUTTON_LEFT and _active_tool_id == BoardToolController.TOOL_HAND
		var is_space_pan: bool = mouse_event.button_index == MOUSE_BUTTON_LEFT and Input.is_action_pressed("board_pan")
		if is_pan_button or is_hand_pan or is_space_pan:
			_is_pointer_panning = mouse_event.pressed
			mouse_default_cursor_shape = Control.CURSOR_DRAG if _is_pointer_panning else _default_cursor()
			if _is_pointer_panning:
				_set_context_ui_suppressed(true)
				# Keep processing while a pointer pan is held. This lets us recover a
				# release that happens outside this Control and restore contextual UI.
				set_process(true)
				_commit_text_editor()
				_cancel_pointer_action()
				grab_focus()
				_mark_interaction()
			else:
				_interaction_idle_seconds = 0.0
				set_process(true)
			accept_event()
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_handle_left_press(mouse_event)
			else:
				_handle_left_release(mouse_event)
			accept_event()
			return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if _is_pointer_panning:
			_pan_by_screen_delta(motion.relative * POINTER_PAN_MULTIPLIER * _camera_sensitivity)
			accept_event()
			return
		if _pointer_action != ACTION_NONE:
			interaction_activity.emit()
			_handle_pointer_motion(motion)
			accept_event()
			return
		_update_hover(motion.position)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo or _editing_entity_id > 0:
		return
	var command_modifier: bool = key_event.ctrl_pressed or key_event.meta_pressed
	if command_modifier and key_event.keycode == KEY_A:
		select_all_text()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_DELETE or key_event.keycode == KEY_BACKSPACE:
		delete_selection()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_F2:
		edit_primary_text(false)
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_ESCAPE:
		if _pointer_action != ACTION_NONE:
			_cancel_pointer_action()
			get_viewport().set_input_as_handled()
		return
	if key_event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		_nudge_selection(key_event)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_recover_pointer_pan_release()


func _recover_pointer_pan_release() -> void:
	if not _is_pointer_panning or _pointer_pan_input_held():
		return
	_is_pointer_panning = false
	mouse_default_cursor_shape = _default_cursor()
	_interaction_idle_seconds = 0.0
	set_process(true)


func _pointer_pan_input_held() -> bool:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return true
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return false
	return _active_tool_id == BoardToolController.TOOL_HAND or Input.is_action_pressed("board_pan")


func _handle_left_press(event: InputEventMouseButton) -> void:
	interaction_activity.emit()
	grab_focus()
	_mark_interaction()
	_pointer_start_screen = event.position
	_pointer_current_screen = event.position
	_pointer_start_world = screen_to_world(event.position)
	_pointer_current_world = _pointer_start_world
	_action_started = false
	if _active_tool_id == BoardToolController.TOOL_FORMULA:
		_commit_text_editor()
		_set_context_ui_suppressed(false)
		formula_create_requested.emit(_pointer_start_world)
		_pointer_action = ACTION_NONE
		return
	if _active_tool_id == BoardToolController.TOOL_TEXT:
		_commit_text_editor()
		_set_context_ui_suppressed(true)
		_pointer_action = ACTION_CREATE_TEXT
		queue_redraw()
		return
	if _active_tool_id == BoardToolController.TOOL_DRAW and _runtime != null:
		_commit_text_editor()
		_set_context_ui_suppressed(true)
		if _drawing_eraser_enabled:
			_begin_stroke_eraser(_pointer_start_world)
		else:
			_begin_stroke_draw(_pointer_start_world)
		return
	if _active_tool_id != BoardToolController.TOOL_SELECT or _runtime == null:
		return
	_commit_text_editor()
	var selected_connector_id: int = _selected_connector_id()
	if selected_connector_id > 0:
		var endpoint_handle: int = _hit_connector_endpoint_handle(event.position, selected_connector_id)
		if endpoint_handle != CONNECTOR_ENDPOINT_NONE:
			_start_connector_rewire(selected_connector_id, endpoint_handle)
			return
		var router_index: int = _hit_connector_router_handle(event.position, selected_connector_id)
		if router_index >= 0:
			if event.double_click:
				_remove_router_point(selected_connector_id, router_index)
			else:
				_start_router_point_move(selected_connector_id, router_index)
			return
	var connection_anchor: int = _hit_connection_handle(event.position)
	if connection_anchor >= 0:
		_start_connection(connection_anchor)
		return
	var handle: int = _hit_resize_handle(event.position)
	if handle != HANDLE_NONE:
		_start_resize(handle)
		return
	var hit: BoardHitResult = _hit_test_selectable(event.position)
	if hit.is_valid():
		if hit.type_id == BoardEntityTypes.CONNECTOR:
			_runtime.selection.set_single(hit.entity_id)
			if event.double_click:
				_add_router_point(hit.entity_id, _pointer_start_world)
			return
		if event.double_click and hit.type_id == BoardEntityTypes.FORMULA:
			_runtime.selection.set_single(hit.entity_id)
			formula_edit_requested.emit(hit.entity_id)
			return
		if event.double_click and hit.type_id == BoardEntityTypes.TEXT:
			_runtime.selection.set_single(hit.entity_id)
			_open_text_editor(hit.entity_id, false)
			return
		if event.double_click and hit.type_id == BoardEntityTypes.VIDEO:
			_runtime.selection.set_single(hit.entity_id)
			var video_asset_id: String = _runtime.model.videos.get_asset_id(hit.entity_id)
			if not video_asset_id.is_empty():
				video_open_requested.emit(video_asset_id, hit.entity_id)
			return
		if event.double_click and hit.type_id == BoardEntityTypes.AUDIO:
			_runtime.selection.set_single(hit.entity_id)
			var audio_asset_id: String = _runtime.model.audios.get_asset_id(hit.entity_id)
			if not audio_asset_id.is_empty():
				audio_open_requested.emit(audio_asset_id, hit.entity_id)
			return
		if event.double_click and hit.type_id == BoardEntityTypes.MODULE:
			_runtime.selection.set_single(hit.entity_id)
			module_open_requested.emit(hit.entity_id)
			return
		if event.double_click and hit.type_id == BoardEntityTypes.NOTE_PORTAL:
			_runtime.selection.set_single(hit.entity_id)
			var note_id: String = _runtime.model.note_portals.get_note_id(hit.entity_id)
			if not note_id.is_empty():
				note_open_requested.emit(note_id, hit.entity_id)
			return
		if event.shift_pressed:
			_runtime.selection.toggle(hit.entity_id)
		elif not _runtime.selection.contains(hit.entity_id):
			_runtime.selection.set_single(hit.entity_id)
		if _runtime.selection.contains(hit.entity_id):
			_start_move()
		return
	_pointer_action = ACTION_MARQUEE
	_set_context_ui_suppressed(true)
	_marquee_additive = event.shift_pressed
	_marquee_base_selection = _runtime.selection.get_selected_ids()
	if not _marquee_additive:
		_runtime.selection.clear()
	queue_redraw()


func _handle_left_release(_event: InputEventMouseButton) -> void:
	match _pointer_action:
		ACTION_MOVE, ACTION_RESIZE:
			_finish_transform_action()
		ACTION_MARQUEE:
			_finish_marquee()
		ACTION_CREATE_TEXT:
			_finish_text_creation()
		ACTION_CONNECT:
			_finish_connection()
		ACTION_REWIRE_CONNECTOR, ACTION_MOVE_ROUTER_POINT:
			_finish_connector_edit()
		ACTION_DRAW_STROKE:
			_finish_stroke_draw()
		ACTION_ERASE_STROKES:
			_finish_stroke_eraser()
	_pointer_action = ACTION_NONE
	_action_started = false
	_resize_handle = HANDLE_NONE
	_connection_source_entity_id = 0
	_connection_target_entity_id = 0
	_reset_connector_edit_state()
	_set_context_ui_suppressed(false)
	_update_hover(get_local_mouse_position())
	queue_redraw()


func _handle_pointer_motion(event: InputEventMouseMotion) -> void:
	_pointer_current_screen = event.position
	_pointer_current_world = screen_to_world(event.position)
	if not _action_started and _pointer_start_screen.distance_to(_pointer_current_screen) >= POINTER_DRAG_THRESHOLD:
		_action_started = true
		if _pointer_action == ACTION_MOVE or _pointer_action == ACTION_RESIZE:
			_begin_live_transform()
	match _pointer_action:
		ACTION_MOVE:
			if _action_started:
				_apply_move_preview()
		ACTION_RESIZE:
			if _action_started:
				_apply_resize_preview()
		ACTION_CONNECT:
			_update_connection_target()
			queue_redraw()
		ACTION_REWIRE_CONNECTOR:
			_update_connector_rewire_target()
			queue_redraw()
		ACTION_MOVE_ROUTER_POINT:
			if _connector_edit_router_index >= 0 and _connector_edit_router_index < _connector_edit_preview_router_points.size():
				_connector_edit_preview_router_points[_connector_edit_router_index] = _pointer_current_world
			queue_redraw()
		ACTION_DRAW_STROKE:
			_append_stroke_point(_pointer_current_world)
		ACTION_ERASE_STROKES:
			_erase_strokes_between(_eraser_last_world, _pointer_current_world)
			_eraser_last_world = _pointer_current_world
			queue_redraw()
		ACTION_MARQUEE, ACTION_CREATE_TEXT:
			queue_redraw()



func _begin_stroke_draw(world_position: Vector2) -> void:
	_pointer_action = ACTION_DRAW_STROKE
	_action_started = true
	_active_stroke_points = PackedVector2Array([world_position])
	_active_stroke_preview = _active_stroke_points.duplicate()
	_pointer_current_world = world_position
	_pointer_current_screen = world_to_screen(world_position)
	queue_redraw()


func _append_stroke_point(world_position: Vector2) -> void:
	if _pointer_action != ACTION_DRAW_STROKE:
		return
	var quality_spacing_scale: float = _runtime.render_policy.stroke_input_spacing_scale if _runtime != null else 1.0
	var spacing: float = maxf(0.6 / maxf(zoom, 0.08), _drawing_width * 0.10) * quality_spacing_scale
	if not _active_stroke_points.is_empty() and _active_stroke_points[_active_stroke_points.size() - 1].distance_squared_to(world_position) < spacing * spacing:
		return
	_active_stroke_points.append(world_position)
	# Avoid huge event gaps on fast mouse movement without exploding point count.
	if _active_stroke_points.size() >= 2:
		var previous: Vector2 = _active_stroke_points[_active_stroke_points.size() - 2]
		var distance: float = previous.distance_to(world_position)
		var max_step: float = maxf(5.0 / maxf(zoom, 0.08), _drawing_width * 1.15)
		if distance > max_step * 1.7:
			_active_stroke_points.remove_at(_active_stroke_points.size() - 1)
			var steps: int = clampi(int(ceil(distance / max_step)), 2, 16)
			for step: int in range(1, steps + 1):
				_active_stroke_points.append(previous.lerp(world_position, float(step) / float(steps)))
	var smoothing_steps: int = _runtime.render_policy.stroke_smoothing_steps if _runtime != null else 3
	# Use the exact same canonical smoothing spacing as CreateStrokeCommand. The
	# live stroke must not visibly change shape when the mouse is released and the
	# transient preview hands off to retained DOD geometry.
	var canonical_smoothing_spacing: float = 1.2 * quality_spacing_scale
	_active_stroke_preview = StrokeGeometry.build_smooth_path(
		_active_stroke_points,
		canonical_smoothing_spacing,
		smoothing_steps
	)
	queue_redraw()


func _finish_stroke_draw() -> void:
	if _runtime == null:
		_active_stroke_points = PackedVector2Array()
		_active_stroke_preview = PackedVector2Array()
		return
	if _active_stroke_points.size() == 1:
		# A click still produces a short round dot/stroke that can be selected later.
		_active_stroke_points.append(_active_stroke_points[0] + Vector2(0.01, 0.01))
	if _active_stroke_points.size() >= 2:
		var command: CreateStrokeCommand = CreateStrokeCommand.new(
			_active_stroke_points,
			_drawing_style_id,
			_drawing_color,
			_drawing_width,
			_drawing_spray_spread,
			_runtime.render_policy.stroke_smoothing_steps,
			_runtime.render_policy.stroke_input_spacing_scale
		)
		if _runtime.commands.execute(command, _runtime):
			if command.created_entity_id > 0:
				_stroke_commit_handoff_ids[command.created_entity_id] = true
				_sync_stroke_renderer_handoff_watch()
			# Do not force the expensive retained stroke rebuild inside the release
			# gesture. The committed stroke stays visible through the handoff overlay
			# and joins the retained batch after the normal quiet-input window.
			_request_stroke_refresh(false)
	_active_stroke_points = PackedVector2Array()
	_active_stroke_preview = PackedVector2Array()
	_mark_interaction()
	_begin_content_handoff_quiet_window()
	queue_redraw()


func _begin_stroke_eraser(world_position: Vector2) -> void:
	_pointer_action = ACTION_ERASE_STROKES
	_action_started = true
	_eraser_pending_ids.clear()
	_eraser_last_world = world_position
	_pointer_current_world = world_position
	_pointer_current_screen = world_to_screen(world_position)
	_erase_strokes_between(world_position, world_position)


func _erase_strokes_between(from_point: Vector2, to_point: Vector2) -> void:
	if _runtime == null:
		return
	var radius: float = _drawing_eraser_radius
	var area: Rect2 = Rect2(from_point, to_point - from_point).abs().grow(radius + 4.0)
	var candidates: PackedInt64Array = _runtime.spatial_index.query_rect(area)
	var changed: bool = false
	for entity_id: int in candidates:
		if _eraser_pending_ids.has(entity_id) or not _runtime.model.strokes.contains(entity_id):
			continue
		var bounds: Rect2 = _runtime.model.get_entity_bounds(entity_id)
		if _runtime.model.strokes.hit_test_segment(entity_id, bounds, from_point, to_point, radius):
			_eraser_pending_ids[entity_id] = true
			changed = true
	if changed:
		if _stroke_renderer != null:
			_stroke_renderer.set_hidden_entity_ids(_eraser_pending_ids)
		if _stroke_handoff_renderer != null:
			_stroke_handoff_renderer.set_hidden_entity_ids(_eraser_pending_ids)
	queue_redraw()


func _finish_stroke_eraser() -> void:
	if _runtime != null and not _eraser_pending_ids.is_empty():
		var ids: PackedInt64Array = PackedInt64Array()
		for raw_id: Variant in _eraser_pending_ids.keys():
			ids.append(int(raw_id))
		var command: DeleteEntitiesCommand = DeleteEntitiesCommand.new(ids)
		_runtime.commands.execute(command, _runtime)
	_eraser_pending_ids.clear()
	if _stroke_renderer != null:
		_stroke_renderer.set_hidden_entity_ids(_hidden_render_ids)
	_sync_stroke_renderer_handoff_watch()
	_request_stroke_refresh(true)
	queue_redraw()

func _start_move() -> void:
	if _runtime == null:
		return
	_pointer_action = ACTION_MOVE
	_set_context_ui_suppressed(true)
	mouse_default_cursor_shape = Control.CURSOR_MOVE
	_action_entity_ids = _runtime.selection.get_selected_ids()
	_capture_action_transforms()


func _start_resize(handle: int) -> void:
	if _runtime == null or _runtime.selection.primary_id <= 0:
		return
	_pointer_action = ACTION_RESIZE
	_set_context_ui_suppressed(true)
	_resize_handle = handle
	mouse_default_cursor_shape = _cursor_for_resize_handle(handle)
	_action_entity_ids = PackedInt64Array([_runtime.selection.primary_id])
	_capture_action_transforms()


func _start_connection(anchor: int) -> void:
	if _runtime == null or _runtime.selection.size() != 1:
		return
	var source_id: int = _runtime.selection.primary_id
	if source_id <= 0 or _runtime.model.get_entity_type(source_id) == BoardEntityTypes.CONNECTOR:
		return
	_pointer_action = ACTION_CONNECT
	_action_started = true
	_set_context_ui_suppressed(true)
	_connection_source_entity_id = source_id
	_connection_source_anchor = anchor
	_connection_target_entity_id = 0
	_connection_target_anchor = ConnectorGeometry.ANCHOR_LEFT


func _selected_connector_id() -> int:
	if _runtime == null or _runtime.selection.size() != 1:
		return 0
	var entity_id: int = _runtime.selection.primary_id
	if entity_id <= 0 or not _runtime.model.connectors.contains(entity_id):
		return 0
	return entity_id


func _start_connector_rewire(connector_id: int, endpoint: int) -> void:
	if _runtime == null or not _runtime.model.connectors.contains(connector_id):
		return
	_pointer_action = ACTION_REWIRE_CONNECTOR
	_action_started = true
	_set_context_ui_suppressed(true)
	_connector_edit_entity_id = connector_id
	_connector_edit_endpoint = endpoint
	_connector_edit_router_index = -1
	_connector_edit_before_record = _runtime.model.connectors.get_record(connector_id)
	_connector_edit_preview_router_points = _runtime.model.connectors.get_router_points(connector_id)
	_connector_edit_candidate_entity_id = 0
	_hidden_connector_ids[connector_id] = true
	_connector_renderer.set_hidden_connector_ids(_hidden_connector_ids)
	_update_connector_rewire_target()


func _start_router_point_move(connector_id: int, router_index: int) -> void:
	if _runtime == null or not _runtime.model.connectors.contains(connector_id):
		return
	var points: PackedVector2Array = _runtime.model.connectors.get_router_points(connector_id)
	if router_index < 0 or router_index >= points.size():
		return
	_pointer_action = ACTION_MOVE_ROUTER_POINT
	_action_started = true
	_set_context_ui_suppressed(true)
	_connector_edit_entity_id = connector_id
	_connector_edit_endpoint = CONNECTOR_ENDPOINT_NONE
	_connector_edit_router_index = router_index
	_connector_edit_before_record = _runtime.model.connectors.get_record(connector_id)
	_connector_edit_preview_router_points = points
	_hidden_connector_ids[connector_id] = true
	_connector_renderer.set_hidden_connector_ids(_hidden_connector_ids)


func _update_connector_rewire_target() -> void:
	_connector_edit_candidate_entity_id = 0
	if _runtime == null or _connector_edit_entity_id <= 0:
		return
	var hit: BoardHitResult = _runtime.hit_test.hit_test_point(
		_pointer_current_world,
		32.0 / maxf(zoom, 0.001)
	)
	if not hit.is_valid() or hit.type_id == BoardEntityTypes.CONNECTOR:
		return
	var fixed_endpoint_id: int = 0
	if _connector_edit_endpoint == CONNECTOR_ENDPOINT_SOURCE:
		fixed_endpoint_id = _runtime.model.connectors.get_target_entity_id(_connector_edit_entity_id)
	else:
		fixed_endpoint_id = _runtime.model.connectors.get_source_entity_id(_connector_edit_entity_id)
	if hit.entity_id == fixed_endpoint_id:
		return
	_connector_edit_candidate_entity_id = hit.entity_id
	_connector_edit_candidate_anchor = ConnectorGeometry.nearest_anchor(
		_runtime.model.get_entity_bounds(hit.entity_id),
		_pointer_current_world
	)


func _finish_connector_edit() -> void:
	if _runtime == null or _connector_edit_entity_id <= 0 or _connector_edit_before_record.is_empty():
		_return_connector_to_batch()
		return
	var after_record: Dictionary = _connector_edit_before_record.duplicate(true)
	var action_label: String = NotLightL10n.text("runtime.board.native_board_view.848c66a086")
	if _pointer_action == ACTION_REWIRE_CONNECTOR:
		if _connector_edit_candidate_entity_id <= 0:
			_return_connector_to_batch()
			return
		if _connector_edit_endpoint == CONNECTOR_ENDPOINT_SOURCE:
			after_record["source_entity_id"] = str(_connector_edit_candidate_entity_id)
			after_record["source_anchor"] = _connector_edit_candidate_anchor
		else:
			after_record["target_entity_id"] = str(_connector_edit_candidate_entity_id)
			after_record["target_anchor"] = _connector_edit_candidate_anchor
		action_label = NotLightL10n.text("runtime.board.native_board_view.c167d6ac6a")
	elif _pointer_action == ACTION_MOVE_ROUTER_POINT:
		after_record["router_points"] = _router_points_to_records(_connector_edit_preview_router_points)
		action_label = NotLightL10n.text("runtime.board.native_board_view.27699abfa0")
	if after_record != _connector_edit_before_record:
		var command: UpdateConnectorCommand = UpdateConnectorCommand.new(
			_connector_edit_entity_id,
			_connector_edit_before_record,
			after_record,
			action_label
		)
		_runtime.commands.execute(command, _runtime)
	_return_connector_to_batch()


func _add_router_point(connector_id: int, world_position: Vector2) -> void:
	if _runtime == null or not _runtime.model.connectors.contains(connector_id):
		return
	var before_record: Dictionary = _runtime.model.connectors.get_record(connector_id)
	var points: PackedVector2Array = _runtime.model.connectors.get_router_points(connector_id)
	var source_id: int = _runtime.model.connectors.get_source_entity_id(connector_id)
	var target_id: int = _runtime.model.connectors.get_target_entity_id(connector_id)
	if not _runtime.model.contains(source_id) or not _runtime.model.contains(target_id):
		return
	var start: Vector2 = ConnectorGeometry.anchor_position(
		_runtime.model.get_entity_bounds(source_id),
		_runtime.model.connectors.get_source_anchor(connector_id)
	)
	var finish: Vector2 = ConnectorGeometry.anchor_position(
		_runtime.model.get_entity_bounds(target_id),
		_runtime.model.connectors.get_target_anchor(connector_id)
	)
	var insertion_index: int = ConnectorGeometry.router_insertion_index(start, finish, points, world_position)
	points.insert(insertion_index, world_position)
	var after_record: Dictionary = before_record.duplicate(true)
	after_record["router_points"] = _router_points_to_records(points)
	var command: UpdateConnectorCommand = UpdateConnectorCommand.new(
		connector_id,
		before_record,
		after_record,
		NotLightL10n.text("runtime.board.native_board_view.90bc425442")
	)
	if _runtime.commands.execute(command, _runtime):
		_refresh_connectors_immediately()
	queue_redraw()


func _remove_router_point(connector_id: int, router_index: int) -> void:
	if _runtime == null or not _runtime.model.connectors.contains(connector_id):
		return
	var points: PackedVector2Array = _runtime.model.connectors.get_router_points(connector_id)
	if router_index < 0 or router_index >= points.size():
		return
	var before_record: Dictionary = _runtime.model.connectors.get_record(connector_id)
	points.remove_at(router_index)
	var after_record: Dictionary = before_record.duplicate(true)
	after_record["router_points"] = _router_points_to_records(points)
	var command: UpdateConnectorCommand = UpdateConnectorCommand.new(
		connector_id,
		before_record,
		after_record,
		NotLightL10n.text("runtime.board.native_board_view.8f672d7d98")
	)
	if _runtime.commands.execute(command, _runtime):
		_refresh_connectors_immediately()
	queue_redraw()


func _return_connector_to_batch() -> void:
	if _connector_edit_entity_id > 0:
		_hidden_connector_ids.erase(_connector_edit_entity_id)
	if _connector_renderer != null:
		_connector_renderer.set_hidden_connector_ids(_hidden_connector_ids, false)
	# Rebuild before the transient edit overlay is dropped. Otherwise the connector
	# spends at least one scheduler frame in neither renderer and visibly blinks.
	_refresh_connectors_immediately()
	queue_redraw()


func _reset_connector_edit_state() -> void:
	_connector_edit_entity_id = 0
	_connector_edit_endpoint = CONNECTOR_ENDPOINT_NONE
	_connector_edit_router_index = -1
	_connector_edit_before_record = {}
	_connector_edit_preview_router_points = PackedVector2Array()
	_connector_edit_candidate_entity_id = 0
	_connector_edit_candidate_anchor = ConnectorGeometry.ANCHOR_LEFT


func _router_points_to_records(points: PackedVector2Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for point: Vector2 in points:
		result.append({"x": point.x, "y": point.y})
	return result


func _capture_action_transforms() -> void:
	_action_before_bounds.clear()
	_action_before_text_records.clear()
	_action_before_rotations = PackedFloat32Array()
	_action_before_rotations.resize(_action_entity_ids.size())
	if _runtime == null:
		return
	for index: int in range(_action_entity_ids.size()):
		var entity_id: int = int(_action_entity_ids[index])
		_action_before_bounds.append(_runtime.model.get_entity_bounds(entity_id))
		_action_before_rotations[index] = _runtime.model.transforms.get_rotation(entity_id)
		_action_before_text_records.append(
			_runtime.model.text_blocks.get_record(entity_id)
			if _runtime.model.text_blocks.contains(entity_id)
			else {}
		)


func _begin_live_transform() -> void:
	if _runtime == null:
		return
	_hidden_render_ids.clear()
	_hidden_connector_ids.clear()
	for entity_id: int in _action_entity_ids:
		_hidden_render_ids[entity_id] = true
		for connector_id: int in _runtime.model.connectors.get_attached_connector_ids(entity_id):
			_hidden_connector_ids[connector_id] = true
	_sync_text_renderer_hidden_ids()
	if _image_renderer != null:
		_image_renderer.set_hidden_entity_ids(_hidden_render_ids)
	if _pdf_renderer != null:
		_pdf_renderer.set_hidden_entity_ids(_hidden_render_ids)
	if _formula_renderer != null:
		_formula_renderer.set_hidden_entity_ids(_hidden_render_ids)
	if _video_renderer != null:
		_video_renderer.set_hidden_entity_ids(_hidden_render_ids)
	if _audio_renderer != null:
		_audio_renderer.set_hidden_entity_ids(_hidden_render_ids)
	if _note_portal_renderer != null:
		_note_portal_renderer.set_hidden_entity_ids(_hidden_render_ids)
	if _stroke_renderer != null:
		_stroke_renderer.set_hidden_entity_ids(_hidden_render_ids)
	_sync_stroke_renderer_handoff_watch()
	if _connector_renderer != null:
		_connector_renderer.set_hidden_connector_ids(_hidden_connector_ids)
	# Schedule the transient connector overlay in the same frame in which retained
	# connectors are hidden, so dragging starts without a one-frame disappearance.
	queue_redraw()
	_runtime.begin_change_batch()
	_request_text_refresh(true)
	_request_image_refresh(true)
	_request_pdf_refresh(true)
	_request_formula_refresh(true)
	_request_video_refresh(true)
	_request_audio_refresh(true)
	_request_note_portal_refresh(true)
	_request_stroke_refresh(true)


func _apply_move_preview() -> void:
	if _runtime == null:
		return
	var delta: Vector2 = _pointer_current_world - _pointer_start_world
	for index: int in range(_action_entity_ids.size()):
		var entity_id: int = int(_action_entity_ids[index])
		var before: Rect2 = _action_before_bounds[index]
		_runtime.set_entity_transform(entity_id, Rect2(before.position + delta, before.size), float(_action_before_rotations[index]))
	queue_redraw()


func _apply_resize_preview() -> void:
	if _runtime == null or _action_before_bounds.is_empty() or _action_entity_ids.is_empty():
		return
	var entity_id: int = int(_action_entity_ids[0])
	var before: Rect2 = _action_before_bounds[0]
	var entity_type: StringName = _runtime.model.get_entity_type(entity_id)
	if entity_type == BoardEntityTypes.NOTE_PORTAL:
		_apply_note_portal_resize_preview(entity_id, before)
		return
	if entity_type == BoardEntityTypes.IMAGE or entity_type == BoardEntityTypes.PDF or entity_type == BoardEntityTypes.VIDEO or entity_type == BoardEntityTypes.AUDIO or entity_type == BoardEntityTypes.STROKE or entity_type == BoardEntityTypes.FORMULA or entity_type == BoardEntityTypes.MODULE:
		_apply_media_resize_preview(entity_id, before)
		return
	var record: Dictionary = _action_before_text_records[0]
	var before_font_size: float = float(record.get("font_size", TextBlockStore.DEFAULT_FONT_SIZE))
	var layout_mode: int = int(record.get("layout_mode", TextBlockStore.LAYOUT_AUTO_WIDTH))
	if _resize_handle == HANDLE_LEFT or _resize_handle == HANDLE_RIGHT:
		var left: float = before.position.x
		var right: float = before.end.x
		if _resize_handle == HANDLE_LEFT:
			left = minf(_pointer_current_world.x, right - MIN_TEXT_SIZE.x)
		else:
			right = maxf(_pointer_current_world.x, left + MIN_TEXT_SIZE.x)
		var width: float = right - left
		var resized: Rect2 = Rect2(Vector2(left, before.position.y), Vector2(width, before.size.y))
		var fixed_record: Dictionary = record.duplicate(true)
		fixed_record["layout_mode"] = TextBlockStore.LAYOUT_FIXED_WIDTH
		resized = TextLayoutUtils.fit_record_bounds(resized, fixed_record, MIN_TEXT_SIZE)
		_runtime.model.text_blocks.set_layout_mode(entity_id, TextBlockStore.LAYOUT_FIXED_WIDTH)
		_runtime.set_entity_transform(entity_id, resized, float(_action_before_rotations[0]))
		queue_redraw()
		return
	var fixed_point: Vector2 = before.end
	match _resize_handle:
		HANDLE_TOP_RIGHT:
			fixed_point = Vector2(before.position.x, before.end.y)
		HANDLE_BOTTOM_RIGHT:
			fixed_point = before.position
		HANDLE_BOTTOM_LEFT:
			fixed_point = Vector2(before.end.x, before.position.y)
	var original_corner: Vector2 = before.position
	match _resize_handle:
		HANDLE_TOP_RIGHT:
			original_corner = Vector2(before.end.x, before.position.y)
		HANDLE_BOTTOM_RIGHT:
			original_corner = before.end
		HANDLE_BOTTOM_LEFT:
			original_corner = Vector2(before.position.x, before.end.y)
	var original_vector: Vector2 = original_corner - fixed_point
	var pointer_vector: Vector2 = _pointer_current_world - fixed_point
	var original_length_squared: float = maxf(original_vector.length_squared(), 1.0)
	var scale_value: float = pointer_vector.dot(original_vector) / original_length_squared
	var minimum_scale: float = maxf(
		MIN_TEXT_SIZE.x / maxf(before.size.x, 1.0),
		TextBlockStore.MIN_FONT_SIZE / maxf(before_font_size, 1.0)
	)
	var maximum_scale: float = TextBlockStore.MAX_FONT_SIZE / maxf(before_font_size, 1.0)
	scale_value = clampf(scale_value, minimum_scale, maximum_scale)
	var next_font_size: float = clampf(before_font_size * scale_value, TextBlockStore.MIN_FONT_SIZE, TextBlockStore.MAX_FONT_SIZE)
	var scaled_width: float = maxf(MIN_TEXT_SIZE.x, before.size.x * scale_value)
	var scaled_record: Dictionary = record.duplicate(true)
	scaled_record["font_size"] = next_font_size
	scaled_record["layout_mode"] = layout_mode
	var fitted_size: Vector2 = TextLayoutUtils.fitted_size_for_record(
		scaled_record,
		scaled_width,
		MIN_TEXT_SIZE
	)
	var new_position: Vector2 = fixed_point - fitted_size
	match _resize_handle:
		HANDLE_TOP_RIGHT:
			new_position = Vector2(fixed_point.x, fixed_point.y - fitted_size.y)
		HANDLE_BOTTOM_RIGHT:
			new_position = fixed_point
		HANDLE_BOTTOM_LEFT:
			new_position = Vector2(fixed_point.x - fitted_size.x, fixed_point.y)
	_runtime.model.text_blocks.set_font_size(entity_id, next_font_size)
	_runtime.set_entity_transform(entity_id, Rect2(new_position, fitted_size), float(_action_before_rotations[0]))
	queue_redraw()


func _apply_note_portal_resize_preview(entity_id: int, before: Rect2) -> void:
	if _runtime == null:
		return
	if (
		_runtime.model.note_portals.contains(entity_id)
		and _runtime.model.note_portals.get_view_mode(entity_id) == NotePortalStore.VIEW_WORKSPACE
	):
		_apply_note_workspace_resize_preview(entity_id, before)
		return
	var left: float = before.position.x
	var top: float = before.position.y
	var right: float = before.end.x
	var bottom: float = before.end.y
	match _resize_handle:
		HANDLE_TOP_LEFT:
			left = minf(_pointer_current_world.x, right - MIN_NOTE_PORTAL_SIZE.x)
			top = minf(_pointer_current_world.y, bottom - MIN_NOTE_PORTAL_SIZE.y)
		HANDLE_TOP:
			top = minf(_pointer_current_world.y, bottom - MIN_NOTE_PORTAL_SIZE.y)
		HANDLE_TOP_RIGHT:
			right = maxf(_pointer_current_world.x, left + MIN_NOTE_PORTAL_SIZE.x)
			top = minf(_pointer_current_world.y, bottom - MIN_NOTE_PORTAL_SIZE.y)
		HANDLE_RIGHT:
			right = maxf(_pointer_current_world.x, left + MIN_NOTE_PORTAL_SIZE.x)
		HANDLE_BOTTOM_RIGHT:
			right = maxf(_pointer_current_world.x, left + MIN_NOTE_PORTAL_SIZE.x)
			bottom = maxf(_pointer_current_world.y, top + MIN_NOTE_PORTAL_SIZE.y)
		HANDLE_BOTTOM:
			bottom = maxf(_pointer_current_world.y, top + MIN_NOTE_PORTAL_SIZE.y)
		HANDLE_BOTTOM_LEFT:
			left = minf(_pointer_current_world.x, right - MIN_NOTE_PORTAL_SIZE.x)
			bottom = maxf(_pointer_current_world.y, top + MIN_NOTE_PORTAL_SIZE.y)
		HANDLE_LEFT:
			left = minf(_pointer_current_world.x, right - MIN_NOTE_PORTAL_SIZE.x)
		_:
			return
	_runtime.set_entity_transform(entity_id, Rect2(Vector2(left, top), Vector2(right - left, bottom - top)), float(_action_before_rotations[0]))
	queue_redraw()


func _apply_note_workspace_resize_preview(entity_id: int, before: Rect2) -> void:
	var aspect: float = before.size.x / maxf(before.size.y, 1.0)
	var anchor: Vector2 = before.end
	var pointer_delta: Vector2 = _pointer_current_world - anchor
	match _resize_handle:
		HANDLE_TOP_LEFT:
			anchor = before.end
			pointer_delta = _pointer_current_world - anchor
		HANDLE_TOP_RIGHT:
			anchor = Vector2(before.position.x, before.end.y)
			pointer_delta = _pointer_current_world - anchor
		HANDLE_BOTTOM_RIGHT:
			anchor = before.position
			pointer_delta = _pointer_current_world - anchor
		HANDLE_BOTTOM_LEFT:
			anchor = Vector2(before.end.x, before.position.y)
			pointer_delta = _pointer_current_world - anchor
		HANDLE_TOP, HANDLE_BOTTOM:
			var desired_height: float = maxf(MIN_NOTE_PORTAL_SIZE.y, absf(_pointer_current_world.y - (before.end.y if _resize_handle == HANDLE_TOP else before.position.y)))
			var desired_size: Vector2 = Vector2(desired_height * aspect, desired_height)
			var center_x: float = before.get_center().x
			var y: float = before.end.y - desired_size.y if _resize_handle == HANDLE_TOP else before.position.y
			_runtime.set_entity_transform(entity_id, Rect2(Vector2(center_x - desired_size.x * 0.5, y), desired_size), float(_action_before_rotations[0]))
			queue_redraw()
			return
		HANDLE_LEFT, HANDLE_RIGHT:
			var desired_width: float = maxf(MIN_NOTE_PORTAL_SIZE.x, absf(_pointer_current_world.x - (before.end.x if _resize_handle == HANDLE_LEFT else before.position.x)))
			var desired_size: Vector2 = Vector2(desired_width, desired_width / maxf(aspect, 0.001))
			var center_y: float = before.get_center().y
			var x: float = before.end.x - desired_size.x if _resize_handle == HANDLE_LEFT else before.position.x
			_runtime.set_entity_transform(entity_id, Rect2(Vector2(x, center_y - desired_size.y * 0.5), desired_size), float(_action_before_rotations[0]))
			queue_redraw()
			return
		_:
			return
	var width_from_x: float = absf(pointer_delta.x)
	var height_from_y: float = absf(pointer_delta.y)
	var scale: float = maxf(width_from_x / maxf(before.size.x, 1.0), height_from_y / maxf(before.size.y, 1.0))
	var min_scale: float = maxf(MIN_NOTE_PORTAL_SIZE.x / maxf(before.size.x, 1.0), MIN_NOTE_PORTAL_SIZE.y / maxf(before.size.y, 1.0))
	scale = maxf(scale, min_scale)
	var new_size: Vector2 = before.size * scale
	var new_position: Vector2 = anchor
	match _resize_handle:
		HANDLE_TOP_LEFT:
			new_position = anchor - new_size
		HANDLE_TOP_RIGHT:
			new_position = Vector2(anchor.x, anchor.y - new_size.y)
		HANDLE_BOTTOM_RIGHT:
			new_position = anchor
		HANDLE_BOTTOM_LEFT:
			new_position = Vector2(anchor.x - new_size.x, anchor.y)
	_runtime.set_entity_transform(entity_id, Rect2(new_position, new_size), float(_action_before_rotations[0]))
	queue_redraw()


func _apply_media_resize_preview(entity_id: int, before: Rect2) -> void:
	if _runtime == null:
		return
	var fixed_point: Vector2 = before.end
	var original_corner: Vector2 = before.position
	match _resize_handle:
		HANDLE_TOP_RIGHT:
			fixed_point = Vector2(before.position.x, before.end.y)
			original_corner = Vector2(before.end.x, before.position.y)
		HANDLE_BOTTOM_RIGHT:
			fixed_point = before.position
			original_corner = before.end
		HANDLE_BOTTOM_LEFT:
			fixed_point = Vector2(before.end.x, before.position.y)
			original_corner = Vector2(before.position.x, before.end.y)
	var original_vector: Vector2 = original_corner - fixed_point
	var pointer_vector: Vector2 = _pointer_current_world - fixed_point
	var scale_value: float = pointer_vector.dot(original_vector) / maxf(original_vector.length_squared(), 1.0)
	var minimum_scale: float = maxf(
		MIN_IMAGE_SIZE.x / maxf(before.size.x, 1.0),
		MIN_IMAGE_SIZE.y / maxf(before.size.y, 1.0)
	)
	scale_value = maxf(scale_value, minimum_scale)
	var next_size: Vector2 = before.size * scale_value
	var next_position: Vector2 = fixed_point - next_size
	match _resize_handle:
		HANDLE_TOP_RIGHT:
			next_position = Vector2(fixed_point.x, fixed_point.y - next_size.y)
		HANDLE_BOTTOM_RIGHT:
			next_position = fixed_point
		HANDLE_BOTTOM_LEFT:
			next_position = Vector2(fixed_point.x - next_size.x, fixed_point.y)
	_runtime.set_entity_transform(entity_id, Rect2(next_position, next_size), float(_action_before_rotations[0]))
	queue_redraw()


func _finish_transform_action() -> void:
	if _runtime == null or not _action_started:
		return
	var after_bounds: Array[Rect2] = []
	var after_rotations: PackedFloat32Array = PackedFloat32Array()
	var after_records: Array[Dictionary] = []
	after_rotations.resize(_action_entity_ids.size())
	var changed: bool = false
	for index: int in range(_action_entity_ids.size()):
		var entity_id: int = int(_action_entity_ids[index])
		var current_bounds: Rect2 = _runtime.model.get_entity_bounds(entity_id)
		after_bounds.append(current_bounds)
		after_rotations[index] = _runtime.model.transforms.get_rotation(entity_id)
		after_records.append(
			_runtime.model.text_blocks.get_record(entity_id)
			if _runtime.model.text_blocks.contains(entity_id)
			else {}
		)
		if current_bounds != _action_before_bounds[index] or after_records[index] != _action_before_text_records[index]:
			changed = true
	_runtime.end_change_batch()
	if changed:
		if _pointer_action == ACTION_RESIZE and _action_entity_ids.size() == 1 and not after_records[0].is_empty():
			var resize_command: UpdateTextPropertiesCommand = UpdateTextPropertiesCommand.new(
				_action_entity_ids,
				_action_before_text_records,
				after_records,
				NotLightL10n.text("runtime.ui.board_screen.b1e23e1ff0"),
				_action_before_bounds,
				after_bounds
			)
			_runtime.commands.record_applied(resize_command)
		else:
			var command: TransformEntitiesCommand = TransformEntitiesCommand.new(
				_action_entity_ids,
				_action_before_bounds,
				after_bounds,
				_action_before_rotations,
				after_rotations
			)
			command.label = NotLightL10n.text("runtime.board.native_board_view.80628800f1") if _pointer_action == ACTION_RESIZE else NotLightL10n.text("runtime.core.transform_entities_command.59a923c4e2")
			command.merge_key = StringName()
			_runtime.commands.record_applied(command)
	_unhide_text_after_plan = not _hidden_render_ids.is_empty()
	_include_hidden_in_text_plan = true
	_request_text_refresh(true)
	_include_hidden_in_text_plan = false
	if _unhide_text_after_plan and not _text_plan_pending:
		_unhide_text_after_plan = false
		_hidden_render_ids.clear()
		_sync_text_renderer_hidden_ids()
	_hidden_connector_ids.clear()
	if _connector_renderer != null:
		_connector_renderer.set_hidden_connector_ids(_hidden_connector_ids, false)
	# Complete the retained/transient handoff synchronously. The normal renderer
	# scheduler deliberately rebuilds only a small number of batches per frame;
	# waiting for it here caused arrows to blink when a connected object was moved.
	_refresh_connectors_immediately()
	_request_image_refresh(true)
	if _image_renderer != null:
		_image_renderer.set_hidden_entity_ids({})
	_request_formula_refresh(true)
	if _formula_renderer != null:
		_formula_renderer.set_hidden_entity_ids({})
	_request_video_refresh(true)
	if _video_renderer != null:
		_video_renderer.set_hidden_entity_ids({})
	_request_audio_refresh(true)
	if _audio_renderer != null:
		_audio_renderer.set_hidden_entity_ids({})
	if _note_portal_renderer != null:
		_note_portal_renderer.set_hidden_entity_ids({})
	_refresh_note_portals_immediately()
	_request_stroke_refresh(true)
	if _stroke_renderer != null:
		_stroke_renderer.set_hidden_entity_ids({})
	_sync_stroke_renderer_handoff_watch()
	_emit_context_anchor()


func _finish_marquee() -> void:
	if _runtime == null or not _action_started:
		return
	var world_rect: Rect2 = _normalized_world_pointer_rect()
	var candidates: PackedInt64Array = _runtime.spatial_index.query_rect(world_rect)
	var selected: PackedInt64Array = _marquee_base_selection.duplicate() if _marquee_additive else PackedInt64Array()
	var selected_lookup: Dictionary = {}
	for existing_id: int in selected:
		selected_lookup[existing_id] = true
	for entity_id: int in candidates:
		if not _runtime.model.contains(entity_id) or _runtime.model.get_entity_type(entity_id) == BoardEntityTypes.CONNECTOR:
			continue
		var bounds: Rect2 = _runtime.model.get_entity_bounds(entity_id)
		if world_rect.intersects(bounds, true) and not selected_lookup.has(entity_id):
			selected.append(entity_id)
			selected_lookup[entity_id] = true
	_runtime.selection.set_many(selected, int(selected[selected.size() - 1]) if not selected.is_empty() else 0)


func _finish_text_creation() -> void:
	if _runtime == null:
		return
	var layout_mode: int = TextBlockStore.LAYOUT_FIXED_WIDTH if _action_started else TextBlockStore.LAYOUT_AUTO_WIDTH
	var bounds: Rect2
	if _action_started:
		bounds = _normalized_world_pointer_rect()
		bounds.size.x = maxf(bounds.size.x, MIN_TEXT_SIZE.x)
		bounds.size.y = maxf(bounds.size.y, 28.0)
	else:
		bounds = Rect2(_pointer_start_world, DEFAULT_TEXT_SIZE)
	var initial_record: Dictionary = {
		"text": "",
		"font_size": TextBlockStore.DEFAULT_FONT_SIZE,
		"font_family": TextBlockStore.DEFAULT_FONT_FAMILY,
		"layout_mode": layout_mode,
		"background_color": Color.TRANSPARENT.to_html(true),
		"text_color": TextBlockStore.COLOR_TEXT.to_html(true),
		"base_style_flags": 0,
		"paragraphs": [],
	}
	bounds = TextLayoutUtils.fit_record_bounds(bounds, initial_record, MIN_TEXT_SIZE)
	var command: CreateTextBlockCommand = CreateTextBlockCommand.new(
		bounds,
		"",
		TextBlockStore.DEFAULT_FONT_SIZE,
		HORIZONTAL_ALIGNMENT_LEFT,
		TextBlockStore.STYLE_PLAIN,
		layout_mode,
		Color.TRANSPARENT,
		TextBlockStore.COLOR_TEXT,
		_runtime.model.get_max_z_order() + 1
	)
	if _runtime.commands.execute(command, _runtime):
		_runtime.selection.set_single(command.created_entity_id)
		_runtime.tools.set_active_tool(BoardToolController.TOOL_SELECT)
		_open_text_editor(command.created_entity_id, false, command)
	_request_text_refresh(true)


func _finish_connection() -> void:
	if _runtime == null or _connection_source_entity_id <= 0 or _connection_target_entity_id <= 0:
		return
	var command: CreateConnectorCommand = CreateConnectorCommand.new(
		_connection_source_entity_id,
		_connection_target_entity_id,
		_connection_source_anchor,
		_connection_target_anchor
	)
	if _runtime.commands.execute(command, _runtime):
		# Creation has no transient retained copy to cover the render scheduler delay.
		# Materialize the new arrow immediately so it appears as one continuous action.
		_refresh_connectors_immediately()


func _update_connection_target() -> void:
	_connection_target_entity_id = 0
	if _runtime == null:
		return
	var hit: BoardHitResult = _runtime.hit_test.hit_test_point(
		_pointer_current_world,
		32.0 / maxf(zoom, 0.001)
	)
	if not hit.is_valid() or hit.entity_id == _connection_source_entity_id:
		return
	_connection_target_entity_id = hit.entity_id
	_connection_target_anchor = ConnectorGeometry.nearest_anchor(
		_runtime.model.get_entity_bounds(hit.entity_id),
		_pointer_current_world
	)


func _cancel_pointer_action() -> void:
	if _pointer_action == ACTION_DRAW_STROKE:
		_active_stroke_points = PackedVector2Array()
		_active_stroke_preview = PackedVector2Array()
	elif _pointer_action == ACTION_ERASE_STROKES:
		_eraser_pending_ids.clear()
		if _stroke_renderer != null:
			_stroke_renderer.set_hidden_entity_ids(_hidden_render_ids)
	_unhide_text_after_plan = false
	if _runtime != null and _action_started and (_pointer_action == ACTION_MOVE or _pointer_action == ACTION_RESIZE):
		for index: int in range(_action_entity_ids.size()):
			var entity_id: int = int(_action_entity_ids[index])
			_runtime.set_entity_transform(entity_id, _action_before_bounds[index], float(_action_before_rotations[index]))
			if index < _action_before_text_records.size() and not _action_before_text_records[index].is_empty():
				_runtime.model.text_blocks.apply_record(entity_id, _action_before_text_records[index])
		_hidden_render_ids.clear()
		_hidden_connector_ids.clear()
		_sync_text_renderer_hidden_ids()
		if _image_renderer != null:
			_image_renderer.set_hidden_entity_ids(_hidden_render_ids)
		if _pdf_renderer != null:
			_pdf_renderer.set_hidden_entity_ids(_hidden_render_ids)
		if _formula_renderer != null:
			_formula_renderer.set_hidden_entity_ids(_hidden_render_ids)
		if _video_renderer != null:
			_video_renderer.set_hidden_entity_ids(_hidden_render_ids)
		if _audio_renderer != null:
			_audio_renderer.set_hidden_entity_ids(_hidden_render_ids)
		if _note_portal_renderer != null:
			_note_portal_renderer.set_hidden_entity_ids(_hidden_render_ids)
		if _stroke_renderer != null:
			_stroke_renderer.set_hidden_entity_ids(_hidden_render_ids)
		if _connector_renderer != null:
			_connector_renderer.set_hidden_connector_ids(_hidden_connector_ids, false)
		_sync_stroke_renderer_handoff_watch()
		_runtime.end_change_batch()
	else:
		_hidden_render_ids.clear()
		_hidden_connector_ids.clear()
		if _text_renderer != null:
			_sync_text_renderer_hidden_ids()
		if _image_renderer != null:
			_image_renderer.set_hidden_entity_ids(_hidden_render_ids)
		if _pdf_renderer != null:
			_pdf_renderer.set_hidden_entity_ids(_hidden_render_ids)
		if _formula_renderer != null:
			_formula_renderer.set_hidden_entity_ids(_hidden_render_ids)
		if _video_renderer != null:
			_video_renderer.set_hidden_entity_ids(_hidden_render_ids)
		if _audio_renderer != null:
			_audio_renderer.set_hidden_entity_ids(_hidden_render_ids)
		if _note_portal_renderer != null:
			_note_portal_renderer.set_hidden_entity_ids(_hidden_render_ids)
		if _stroke_renderer != null:
			_stroke_renderer.set_hidden_entity_ids(_hidden_render_ids)
		if _connector_renderer != null:
			_connector_renderer.set_hidden_connector_ids(_hidden_connector_ids, false)
		_sync_stroke_renderer_handoff_watch()
	_pointer_action = ACTION_NONE
	_action_started = false
	_resize_handle = HANDLE_NONE
	_connection_source_entity_id = 0
	_connection_target_entity_id = 0
	_reset_connector_edit_state()
	_set_context_ui_suppressed(false)
	_update_hover(get_local_mouse_position())
	_request_text_refresh(true)
	_request_image_refresh(true)
	_request_pdf_refresh(true)
	_request_formula_refresh(true)
	_request_video_refresh(true)
	_request_audio_refresh(true)
	_refresh_note_portals_immediately()
	_request_stroke_refresh(true)
	_refresh_connectors_immediately()
	queue_redraw()


func _nudge_selection(event: InputEventKey) -> void:
	if _runtime == null or _runtime.selection.size() == 0:
		return
	var amount: float = 10.0 if event.shift_pressed else 1.0
	var delta: Vector2 = Vector2.ZERO
	match event.keycode:
		KEY_LEFT:
			delta.x = -amount
		KEY_RIGHT:
			delta.x = amount
		KEY_UP:
			delta.y = -amount
		KEY_DOWN:
			delta.y = amount
	var ids: PackedInt64Array = PackedInt64Array()
	for selected_id: int in _runtime.selection.get_selected_ids():
		if _runtime.model.get_entity_type(selected_id) != BoardEntityTypes.CONNECTOR:
			ids.append(selected_id)
	if ids.is_empty():
		return
	var before: Array[Rect2] = []
	var after: Array[Rect2] = []
	var rotations: PackedFloat32Array = PackedFloat32Array()
	rotations.resize(ids.size())
	for index: int in range(ids.size()):
		var entity_id: int = int(ids[index])
		var bounds: Rect2 = _runtime.model.get_entity_bounds(entity_id)
		before.append(bounds)
		after.append(Rect2(bounds.position + delta, bounds.size))
		rotations[index] = _runtime.model.transforms.get_rotation(entity_id)
	var command: TransformEntitiesCommand = TransformEntitiesCommand.new(ids, before, after, rotations, rotations)
	command.label = NotLightL10n.text("runtime.core.transform_entities_command.59a923c4e2")
	_runtime.commands.execute(command, _runtime)


func _open_text_editor(
	entity_id: int,
	select_all: bool,
	creation_command: CreateTextBlockCommand = null
) -> void:
	if _runtime == null or not _runtime.model.text_blocks.contains(entity_id):
		return
	if _editing_entity_id > 0 and _editing_entity_id != entity_id:
		_commit_text_editor()
	_editing_entity_id = entity_id
	_editing_creation_command = creation_command
	_editing_initial_record = _runtime.model.text_blocks.get_record(entity_id).duplicate(true)
	_editing_initial_text = str(_editing_initial_record.get("text", ""))
	_editor_last_text = _editing_initial_text
	_editor_typing_style_flags = int(_editing_initial_record.get("base_style_flags", 0))
	_editor_typing_color = Color.from_string(
		str(_editing_initial_record.get("text_color", TextBlockStore.COLOR_TEXT.to_html(true))),
		TextBlockStore.COLOR_TEXT
	)
	_editor_typing_override_active = false
	_editing_initial_bounds = _runtime.model.get_entity_bounds(entity_id)
	_editing_preview_bounds = _editing_initial_bounds
	_sync_text_renderer_hidden_ids()
	_editor_text_mutation_guard = true
	_text_editor.text = _editing_initial_text
	_editor_text_mutation_guard = false
	_update_editing_preview_bounds()
	_text_editor.visible = true
	_text_editor.editable = true
	_update_text_editor_style()
	if zoom < 0.55:
		set_zoom(0.72, world_to_screen(_editing_preview_bounds.get_center()))
	_update_text_editor_layout()
	_text_editor.grab_focus()
	_text_editor.set_caret_line(_text_editor.get_line_count() - 1)
	_text_editor.set_caret_column(_text_editor.get_line(_text_editor.get_caret_line()).length())
	if select_all:
		_text_editor.select_all()
	_reset_editor_caret_blink()
	# The retained plan may keep the old block while editing because the hidden-ID
	# mask already removes it atomically. Avoid rebuilding every visible text block
	# just for entering edit mode; camera/LOD changes can still refresh normally.
	queue_redraw()
	text_editor_state_changed.emit(entity_id)
	text_editor_format_changed.emit()
	_emit_context_anchor()


func _commit_text_editor() -> void:
	if _editing_entity_id <= 0 or _editor_closing:
		return
	_editor_closing = true
	var entity_id: int = _editing_entity_id
	var final_bounds: Rect2 = _editing_preview_bounds
	var creation_command: CreateTextBlockCommand = _editing_creation_command
	var final_record: Dictionary = {}
	if _runtime != null and _runtime.model.text_blocks.contains(entity_id):
		final_record = _runtime.model.text_blocks.get_record(entity_id).duplicate(true)
	_stop_editor_caret_blink()
	_text_editor.visible = false
	_text_editor.release_focus()
	if _runtime != null and creation_command != null:
		if str(final_record.get("text", "")).strip_edges().is_empty():
			_runtime.commands.discard_last_applied(creation_command, _runtime)
		elif _runtime.model.text_blocks.contains(entity_id):
			creation_command.set_final_state(final_record, final_bounds)
			_runtime.set_entity_transform(entity_id, final_bounds, _runtime.model.transforms.get_rotation(entity_id))
	elif _runtime != null and _runtime.model.text_blocks.contains(entity_id):
		if final_record != _editing_initial_record or final_bounds != _editing_initial_bounds:
			_runtime.set_entity_transform(entity_id, final_bounds, _runtime.model.transforms.get_rotation(entity_id))
			var ids: PackedInt64Array = PackedInt64Array([entity_id])
			var before_records: Array[Dictionary] = [_editing_initial_record.duplicate(true)]
			var after_records: Array[Dictionary] = [final_record.duplicate(true)]
			var before_bounds: Array[Rect2] = [_editing_initial_bounds]
			var after_bounds: Array[Rect2] = [final_bounds]
			var command: UpdateTextPropertiesCommand = UpdateTextPropertiesCommand.new(
				ids,
				before_records,
				after_records,
				NotLightL10n.text("runtime.core.edit_text_block_command.1c0ed46897"),
				before_bounds,
				after_bounds
			)
			_runtime.commands.record_applied(command)
	if (
		_runtime != null
		and _runtime.model.text_blocks.contains(entity_id)
		and (
			_render_editing_id == entity_id
			or _render_model_revision != _runtime.model.text_revision
		)
	):
		# If the retained plan still contains this exact unchanged block, simply
		# unhide it. Otherwise keep the final transient copy until the worker plan
		# matching the new text revision has been applied.
		_text_commit_handoff_ids[entity_id] = true
	_editing_entity_id = 0
	_editing_creation_command = null
	_editing_initial_text = ""
	_editor_last_text = ""
	_editor_typing_style_flags = 0
	_editor_typing_color = TextBlockStore.COLOR_TEXT
	_editor_typing_override_active = false
	_editing_initial_record = {}
	_editing_initial_bounds = Rect2()
	_editing_preview_bounds = Rect2()
	_editor_closing = false
	_sync_text_renderer_hidden_ids()
	_begin_content_handoff_quiet_window()
	_request_text_refresh(false)
	_request_connector_refresh(false)
	queue_redraw()
	text_editor_state_changed.emit(0)
	text_editor_format_changed.emit()
	_emit_context_anchor()


func _cancel_text_editor() -> void:
	if _editing_entity_id <= 0:
		return
	_editor_closing = true
	var entity_id: int = _editing_entity_id
	var creation_command: CreateTextBlockCommand = _editing_creation_command
	_stop_editor_caret_blink()
	_text_editor.visible = false
	_text_editor.release_focus()
	if _runtime != null and creation_command != null:
		_runtime.commands.discard_last_applied(creation_command, _runtime)
	elif _runtime != null and _runtime.model.text_blocks.contains(entity_id):
		_runtime.begin_change_batch()
		_runtime.model.text_blocks.apply_record(entity_id, _editing_initial_record)
		_runtime.set_entity_transform(entity_id, _editing_initial_bounds, _runtime.model.transforms.get_rotation(entity_id))
		_runtime.end_change_batch()
	if (
		_runtime != null
		and _runtime.model.text_blocks.contains(entity_id)
		and (
			_render_editing_id == entity_id
			or _render_model_revision != _runtime.model.text_revision
		)
	):
		# If the retained plan still contains this exact unchanged block, simply
		# unhide it. Otherwise keep the final transient copy until the worker plan
		# matching the new text revision has been applied.
		_text_commit_handoff_ids[entity_id] = true
	_editing_entity_id = 0
	_editing_creation_command = null
	_editing_initial_text = ""
	_editor_last_text = ""
	_editor_typing_style_flags = 0
	_editor_typing_color = TextBlockStore.COLOR_TEXT
	_editor_typing_override_active = false
	_editing_initial_record = {}
	_editing_initial_bounds = Rect2()
	_editing_preview_bounds = Rect2()
	_editor_closing = false
	_sync_text_renderer_hidden_ids()
	_begin_content_handoff_quiet_window()
	_request_text_refresh(false)
	_request_connector_refresh(false)
	queue_redraw()
	text_editor_state_changed.emit(0)
	text_editor_format_changed.emit()
	_emit_context_anchor()


func _on_text_editor_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			call_deferred("_sync_editor_typing_style_from_caret", true)
		return
	if event is not InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var command_modifier: bool = key_event.ctrl_pressed or key_event.meta_pressed
	if command_modifier and key_event.keycode == KEY_ENTER:
		_commit_text_editor()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_ESCAPE:
		_cancel_text_editor()
		get_viewport().set_input_as_handled()
		return
	if command_modifier and key_event.keycode == KEY_B:
		_toggle_editor_style_flag(TextBlockStore.FONT_STYLE_BOLD)
		get_viewport().set_input_as_handled()
		return
	if command_modifier and key_event.keycode == KEY_I:
		_toggle_editor_style_flag(TextBlockStore.FONT_STYLE_ITALIC)
		get_viewport().set_input_as_handled()
		return
	if command_modifier and key_event.keycode == KEY_U:
		_toggle_editor_style_flag(TextBlockStore.FONT_STYLE_UNDERLINE)
		get_viewport().set_input_as_handled()
		return
	if command_modifier and key_event.shift_pressed and key_event.keycode == KEY_X:
		_toggle_editor_style_flag(TextBlockStore.FONT_STYLE_STRIKETHROUGH)
		get_viewport().set_input_as_handled()
		return
	if command_modifier and key_event.shift_pressed and key_event.keycode == KEY_7:
		apply_editor_list_type(TextBlockStore.LIST_NUMBERED)
		get_viewport().set_input_as_handled()
		return
	if command_modifier and key_event.shift_pressed and key_event.keycode == KEY_8:
		apply_editor_list_type(TextBlockStore.LIST_BULLET)
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_BACKSPACE and _try_handle_list_backspace():
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN]:
		call_deferred("_sync_editor_typing_style_from_caret", true)
	if key_event.keycode == KEY_TAB and _current_editor_paragraph_is_list():
		adjust_editor_list_indent(-1 if key_event.shift_pressed else 1)
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_ENTER and _current_editor_paragraph_is_empty_list():
		var paragraph_index: int = TextBlockStore.paragraph_index_for_offset(_text_editor.text, _editor_caret_character_offset())
		var indices: PackedInt32Array = PackedInt32Array([paragraph_index])
		_runtime.model.text_blocks.set_paragraph_list_type(_editing_entity_id, indices, TextBlockStore.LIST_NONE)
		_refresh_active_editor_after_format(true)
		get_viewport().set_input_as_handled()


func _on_text_editor_focus_exited() -> void:
	# Toolbar popups should not terminate an editing session. Clicking the board,
	# changing selection, saving, undoing or leaving the board commits explicitly.
	pass


func _on_text_editor_text_changed() -> void:
	if _editing_entity_id <= 0 or _editor_closing or _editor_text_mutation_guard or _runtime == null:
		return
	var previous_text: String = _editor_last_text
	var previous_paragraphs: Array[Dictionary] = _runtime.model.text_blocks.get_paragraphs(_editing_entity_id)
	_runtime.model.text_blocks.set_text(_editing_entity_id, _text_editor.text)
	_apply_pending_typing_style(previous_text, _text_editor.text)
	_inherit_list_metadata_after_newline(previous_text, previous_paragraphs)
	_detect_auto_list_prefix()
	_editor_last_text = _text_editor.text
	_update_editing_preview_bounds()
	_update_text_editor_style()
	_update_text_editor_layout()
	_reset_editor_caret_blink()
	queue_redraw()
	text_editor_format_changed.emit()
	_emit_context_anchor()


func _update_editing_preview_bounds() -> void:
	if _runtime == null or _editing_entity_id <= 0:
		return
	var record: Dictionary = _runtime.model.text_blocks.get_record(_editing_entity_id)
	_editing_preview_bounds = TextLayoutUtils.fit_record_bounds(
		_editing_initial_bounds,
		record,
		MIN_TEXT_SIZE
	)


func _update_text_editor_layout() -> void:
	if _runtime == null or _editing_entity_id <= 0 or not _runtime.model.contains(_editing_entity_id):
		return
	var bounds: Rect2 = _editing_preview_bounds
	var screen_position: Vector2 = world_to_screen(bounds.position)
	var screen_size: Vector2 = bounds.size * zoom
	_text_editor.position = screen_position
	_text_editor.size = Vector2(maxf(screen_size.x, 72.0), maxf(screen_size.y, 32.0))
	var world_font_size: float = _runtime.model.text_blocks.get_font_size(_editing_entity_id)
	_text_editor.add_theme_font_size_override("font_size", clampi(int(round(world_font_size * zoom)), 10, 512))


func _update_text_editor_style() -> void:
	if _runtime == null or _editing_entity_id <= 0:
		return
	var record: Dictionary = _runtime.model.text_blocks.get_record(_editing_entity_id)
	# Native TextEdit is input-only while the board owns every visible glyph.
	# Keeping its placeholder empty prevents a native placeholder from reappearing
	# over semantic markers when an empty paragraph becomes a list.
	_text_editor.placeholder_text = ""
	var background: Color = _runtime.model.text_blocks.get_background_color(_editing_entity_id)
	var foreground: Color = _runtime.model.text_blocks.get_text_color(_editing_entity_id)
	var padding: Vector2 = TextLayoutUtils.padding_for_background(background) * zoom
	var family: String = str(record.get("font_family", TextBlockStore.DEFAULT_FONT_FAMILY))
	var base_flags: int = int(record.get("base_style_flags", 0))
	var font: Font = _font_registry.get_font(family, base_flags)
	_text_editor.add_theme_font_override("font", font)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color.TRANSPARENT
	style.set_border_width_all(0)
	style.set_corner_radius_all(clampi(int(round(12.0 * zoom)), 4, 16))
	style.content_margin_left = maxf(2.0, padding.x)
	style.content_margin_right = maxf(2.0, padding.x)
	style.content_margin_top = maxf(2.0, padding.y)
	style.content_margin_bottom = maxf(2.0, padding.y)
	_text_editor.add_theme_stylebox_override("normal", style)
	_text_editor.add_theme_stylebox_override("focus", style)
	# Text, selection and caret geometry are drawn by the board from one shared
	# rich-text layout. TextEdit remains the single materialized input/IME/clipboard
	# owner and supplies only the logical caret/selection state.
	_text_editor.add_theme_color_override("font_color", Color(foreground, 0.0))
	_text_editor.add_theme_color_override("font_selected_color", Color(foreground, 0.0))
	_text_editor.add_theme_color_override("font_readonly_color", Color(foreground, 0.0))
	_text_editor.add_theme_color_override("caret_color", Color.TRANSPARENT)
	_text_editor.add_theme_color_override("selection_color", Color.TRANSPARENT)
	_text_editor.add_theme_color_override("font_placeholder_color", Color(NotLightTheme.semantic_color("text_muted"), 0.78))


func _has_active_text_editor() -> bool:
	return _runtime != null and _editing_entity_id > 0 and _runtime.model.text_blocks.contains(_editing_entity_id)


func _refresh_active_editor_after_format(recalculate_bounds: bool) -> void:
	if not _has_active_text_editor():
		return
	if recalculate_bounds:
		_update_editing_preview_bounds()
	_update_text_editor_style()
	_update_text_editor_layout()
	queue_redraw()
	text_editor_format_changed.emit()
	_emit_context_anchor()


func _toggle_editor_style_flag(flag: int) -> void:
	var context: Dictionary = get_editor_format_context()
	var flags: int = int(context.get("style_flags", 0))
	apply_editor_style_flag(flag, (flags & flag) == 0)


func _editor_character_range() -> Vector2i:
	if _text_editor == null:
		return Vector2i.ZERO
	if _text_editor.has_selection(0):
		var start: int = _character_offset_for_line_column(
			_text_editor.get_selection_from_line(0),
			_text_editor.get_selection_from_column(0)
		)
		var finish: int = _character_offset_for_line_column(
			_text_editor.get_selection_to_line(0),
			_text_editor.get_selection_to_column(0)
		)
		return Vector2i(mini(start, finish), maxi(start, finish))
	var caret: int = _editor_caret_character_offset()
	return Vector2i(caret, caret)


func _editor_caret_character_offset() -> int:
	if _text_editor == null:
		return 0
	return _character_offset_for_line_column(_text_editor.get_caret_line(), _text_editor.get_caret_column())


func _character_offset_for_line_column(line: int, column: int) -> int:
	if _text_editor == null:
		return 0
	var safe_line: int = clampi(line, 0, maxi(0, _text_editor.get_line_count() - 1))
	var offset: int = 0
	for line_index: int in range(safe_line):
		offset += _text_editor.get_line(line_index).length() + 1
	return offset + clampi(column, 0, _text_editor.get_line(safe_line).length())


func _current_editor_paragraph_is_list() -> bool:
	if not _has_active_text_editor():
		return false
	var paragraph_index: int = TextBlockStore.paragraph_index_for_offset(_text_editor.text, _editor_caret_character_offset())
	return _runtime.model.text_blocks.get_paragraph_list_type(_editing_entity_id, paragraph_index) != TextBlockStore.LIST_NONE


func _current_editor_paragraph_is_empty_list() -> bool:
	if not _current_editor_paragraph_is_list():
		return false
	var line: int = clampi(_text_editor.get_caret_line(), 0, maxi(0, _text_editor.get_line_count() - 1))
	return _text_editor.get_line(line).strip_edges().is_empty()


func _try_handle_list_backspace() -> bool:
	if not _current_editor_paragraph_is_list() or _text_editor.has_selection(0) or _text_editor.get_caret_column() != 0:
		return false
	var paragraph_index: int = TextBlockStore.paragraph_index_for_offset(_text_editor.text, _editor_caret_character_offset())
	var indent: int = _runtime.model.text_blocks.get_paragraph_indent(_editing_entity_id, paragraph_index)
	var indices: PackedInt32Array = PackedInt32Array()
	indices.append(paragraph_index)
	if indent > 0:
		_runtime.model.text_blocks.adjust_paragraph_indent(_editing_entity_id, indices, -1)
	else:
		_runtime.model.text_blocks.set_paragraph_list_type(_editing_entity_id, indices, TextBlockStore.LIST_NONE)
	_refresh_active_editor_after_format(true)
	return true


func _inherit_list_metadata_after_newline(previous_text: String, previous_paragraphs: Array[Dictionary]) -> void:
	if not _has_active_text_editor():
		return
	var previous_count: int = TextBlockStore.paragraph_count_for_text(previous_text)
	var current_count: int = TextBlockStore.paragraph_count_for_text(_text_editor.text)
	if current_count <= previous_count or previous_paragraphs.is_empty():
		return
	var current_paragraph: int = TextBlockStore.paragraph_index_for_offset(_text_editor.text, _editor_caret_character_offset())
	if current_paragraph <= 0:
		return
	var source_index: int = mini(current_paragraph - 1, previous_paragraphs.size() - 1)
	var source: Dictionary = previous_paragraphs[source_index]
	var list_type: int = int(source.get("list_type", TextBlockStore.LIST_NONE))
	if list_type == TextBlockStore.LIST_NONE:
		return
	var indices: PackedInt32Array = PackedInt32Array([current_paragraph])
	_runtime.model.text_blocks.set_paragraph_list_type(_editing_entity_id, indices, list_type)
	var indent: int = int(source.get("indent", 0))
	if indent > 0:
		_runtime.model.text_blocks.adjust_paragraph_indent(_editing_entity_id, indices, indent)


func _detect_auto_list_prefix() -> void:
	if not _has_active_text_editor():
		return
	var line: int = clampi(_text_editor.get_caret_line(), 0, maxi(0, _text_editor.get_line_count() - 1))
	var source: String = _text_editor.get_line(line)
	var list_type: int = TextBlockStore.LIST_NONE
	var prefix_length: int = 0
	if source.begins_with("- ") or source.begins_with("* ") or source.begins_with("• "):
		list_type = TextBlockStore.LIST_BULLET
		prefix_length = 2
	else:
		var marker_end: int = source.find(". ")
		if marker_end > 0 and marker_end <= 4 and source.left(marker_end).is_valid_int():
			list_type = TextBlockStore.LIST_NUMBERED
			prefix_length = marker_end + 2
	if list_type == TextBlockStore.LIST_NONE or prefix_length <= 0:
		return
	var previous_column: int = _text_editor.get_caret_column()
	_editor_text_mutation_guard = true
	_text_editor.set_line(line, source.substr(prefix_length))
	_text_editor.set_caret_line(line)
	_text_editor.set_caret_column(maxi(0, previous_column - prefix_length))
	_editor_text_mutation_guard = false
	_runtime.model.text_blocks.set_text(_editing_entity_id, _text_editor.text)
	var paragraph_index: int = TextBlockStore.paragraph_index_for_offset(_text_editor.text, _editor_caret_character_offset())
	var indices: PackedInt32Array = PackedInt32Array([paragraph_index])
	_runtime.model.text_blocks.set_paragraph_list_type(_editing_entity_id, indices, list_type)
	_text_editor.placeholder_text = ""
	_editor_last_text = _text_editor.text
	_update_editing_preview_bounds()
	_update_text_editor_layout()
	queue_redraw()
	text_editor_format_changed.emit()


func _sync_editor_typing_style_from_caret(clear_override: bool) -> void:
	if not _has_active_text_editor():
		return
	var caret_offset: int = _editor_caret_character_offset()
	var sample_offset: int = caret_offset
	if sample_offset > 0:
		sample_offset -= 1
	var style: Dictionary = _runtime.model.text_blocks.get_style_at(_editing_entity_id, sample_offset)
	_editor_typing_style_flags = int(style.get("flags", 0)) & TextBlockStore.FONT_STYLE_ALL
	var style_color: Variant = style.get("color", TextBlockStore.COLOR_TEXT)
	if style_color is Color:
		_editor_typing_color = style_color as Color
	else:
		_editor_typing_color = Color.from_string(str(style_color), TextBlockStore.COLOR_TEXT)
	if clear_override:
		_editor_typing_override_active = false


func _apply_pending_typing_style(previous_text: String, current_text: String) -> void:
	if not _editor_typing_override_active or not _has_active_text_editor() or current_text.length() <= previous_text.length():
		return
	var prefix: int = _common_text_prefix_length(previous_text, current_text)
	var suffix: int = _common_text_suffix_length(previous_text, current_text, prefix)
	var inserted_length: int = current_text.length() - prefix - suffix
	if inserted_length <= 0:
		return
	_runtime.model.text_blocks.apply_style_range(
		_editing_entity_id,
		prefix,
		prefix + inserted_length,
		_editor_typing_style_flags,
		_editor_typing_color
	)


func _common_text_prefix_length(left: String, right: String) -> int:
	var limit: int = mini(left.length(), right.length())
	var result: int = 0
	while result < limit and left.substr(result, 1) == right.substr(result, 1):
		result += 1
	return result


func _common_text_suffix_length(left: String, right: String, prefix: int) -> int:
	var limit: int = mini(left.length(), right.length()) - prefix
	var result: int = 0
	while (
		result < limit
		and left.substr(left.length() - result - 1, 1) == right.substr(right.length() - result - 1, 1)
	):
		result += 1
	return result


func _on_text_editor_caret_changed() -> void:
	if _editing_entity_id <= 0 or _editor_closing:
		return
	_reset_editor_caret_blink()
	text_editor_format_changed.emit()


func _on_editor_caret_blink_timeout() -> void:
	if not _has_active_text_editor():
		_stop_editor_caret_blink()
		return
	_editor_caret_visible = not _editor_caret_visible
	queue_redraw()


func _reset_editor_caret_blink() -> void:
	_editor_caret_visible = true
	if _editor_caret_timer != null:
		_editor_caret_timer.start()
	queue_redraw()


func _stop_editor_caret_blink() -> void:
	if _editor_caret_timer != null:
		_editor_caret_timer.stop()
	_editor_caret_visible = false
	queue_redraw()


func _draw_editor_selection_overlay() -> void:
	if not _has_active_text_editor() or _text_editor == null or not _text_editor.visible or not _text_editor.has_selection(0):
		return
	var selection_start: int = _character_offset_for_line_column(
		_text_editor.get_selection_from_line(0),
		_text_editor.get_selection_from_column(0)
	)
	var selection_end: int = _character_offset_for_line_column(
		_text_editor.get_selection_to_line(0),
		_text_editor.get_selection_to_column(0)
	)
	if selection_end <= selection_start:
		return
	var record: Dictionary = _runtime.model.text_blocks.get_record(_editing_entity_id)
	var screen_rect: Rect2 = Rect2(
		world_to_screen(_editing_preview_bounds.position),
		_editing_preview_bounds.size * zoom
	)
	var layout: Dictionary = _build_rich_text_screen_layout(record, screen_rect, zoom)
	if layout.is_empty():
		return
	var family: String = str(layout.get("family", TextBlockStore.DEFAULT_FONT_FAMILY))
	var font_size: int = int(layout.get("font_size", 12))
	var screen_font_size: float = float(layout.get("screen_font_size", float(font_size)))
	var base_flags: int = int(layout.get("base_flags", 0))
	var base_color: Color = layout.get("base_color", TextBlockStore.COLOR_TEXT) as Color
	var runs: Array = layout.get("runs", []) as Array
	var raw_lines: Variant = layout.get("lines", [])
	if raw_lines is not Array:
		return
	var selection_color: Color = Color(NotLightTheme.semantic_color("accent"), 0.20)
	for raw_line: Variant in raw_lines as Array:
		if raw_line is not Dictionary:
			continue
		var line: Dictionary = raw_line as Dictionary
		var line_text: String = str(line.get("text", ""))
		var line_start: int = int(line.get("start", 0))
		var line_length: int = mini(int(line.get("length", line_text.length())), line_text.length())
		var line_end: int = line_start + line_length
		var segment_start: int = maxi(selection_start, line_start)
		var segment_end: int = mini(selection_end, line_end)
		if segment_end <= segment_start:
			continue
		var before_count: int = segment_start - line_start
		var selected_count: int = segment_end - segment_start
		var before_text: String = line_text.substr(0, before_count)
		var selected_text: String = line_text.substr(before_count, selected_count)
		var before_spans: Array[Dictionary] = _rich_spans_for_line(
			before_text,
			line_start,
			before_count,
			runs,
			base_flags,
			base_color
		)
		var selected_spans: Array[Dictionary] = _rich_spans_for_line(
			selected_text,
			segment_start,
			selected_count,
			runs,
			base_flags,
			base_color
		)
		var x: float = float(line.get("content_x", screen_rect.position.x))
		x += _rich_span_width(before_spans, family, font_size)
		var width: float = _rich_span_width(selected_spans, family, font_size)
		if width <= 0.0:
			continue
		var baseline_y: float = float(line.get("baseline_y", screen_rect.position.y + screen_font_size))
		var line_height: float = TextLayoutUtils.line_height(screen_font_size)
		var top_y: float = baseline_y - screen_font_size * 0.90
		draw_rect(Rect2(Vector2(x, top_y), Vector2(width, line_height)), selection_color, true)


func _draw_editor_caret_overlay() -> void:
	if not _editor_caret_visible or not _has_active_text_editor() or _text_editor == null or not _text_editor.visible:
		return
	var record: Dictionary = _runtime.model.text_blocks.get_record(_editing_entity_id)
	var screen_rect: Rect2 = Rect2(
		world_to_screen(_editing_preview_bounds.position),
		_editing_preview_bounds.size * zoom
	)
	var layout: Dictionary = _build_rich_text_screen_layout(record, screen_rect, zoom)
	if layout.is_empty():
		return
	var raw_lines: Variant = layout.get("lines", [])
	if raw_lines is not Array or (raw_lines as Array).is_empty():
		return
	var lines: Array = raw_lines as Array
	var caret_offset: int = _editor_caret_character_offset()
	var selected_line_index: int = _visual_line_index_for_character_offset(lines, caret_offset)
	var selected_raw: Variant = lines[selected_line_index]
	if selected_raw is not Dictionary:
		return
	var selected_line: Dictionary = selected_raw as Dictionary
	var line_text: String = str(selected_line.get("text", ""))
	var line_start: int = int(selected_line.get("start", 0))
	var line_length: int = int(selected_line.get("length", line_text.length()))
	var local_character_count: int = clampi(caret_offset - line_start, 0, mini(line_length, line_text.length()))
	var family: String = str(layout.get("family", TextBlockStore.DEFAULT_FONT_FAMILY))
	var font_size: int = int(layout.get("font_size", 12))
	var base_flags: int = int(layout.get("base_flags", 0))
	var base_color: Color = layout.get("base_color", TextBlockStore.COLOR_TEXT) as Color
	var runs: Array = layout.get("runs", []) as Array
	var caret_prefix_text: String = line_text.substr(0, local_character_count)
	var caret_spans: Array[Dictionary] = _rich_spans_for_line(
		caret_prefix_text,
		line_start,
		local_character_count,
		runs,
		base_flags,
		base_color
	)
	var caret_x: float = float(selected_line.get("content_x", screen_rect.position.x))
	caret_x += _rich_span_width(caret_spans, family, font_size)
	var sample_offset: int = caret_offset - 1 if caret_offset > 0 else caret_offset
	var caret_style: Dictionary = _runtime.model.text_blocks.get_style_at(_editing_entity_id, sample_offset)
	var caret_flags: int = int(caret_style.get("flags", base_flags))
	var caret_font: Font = _font_registry.get_font(family, caret_flags)
	var baseline_y: float = float(selected_line.get("baseline_y", screen_rect.position.y + float(font_size)))
	var top_y: float = baseline_y - caret_font.get_ascent(font_size)
	var bottom_y: float = baseline_y + caret_font.get_descent(font_size)
	if bottom_y - top_y < 8.0:
		bottom_y = top_y + maxf(8.0, float(font_size))
	var caret_color: Color = Color(NotLightTheme.semantic_color("accent"), 0.98)
	draw_line(
		Vector2(caret_x, top_y),
		Vector2(caret_x, bottom_y),
		caret_color,
		1.65,
		true
	)


func _visual_line_index_for_character_offset(lines: Array, character_offset: int) -> int:
	# Soft wrapping may omit whitespace at the beginning of the next visual line.
	# In that gap the logical TextEdit caret must still appear at the beginning of
	# the following visual line instead of jumping back to the previous line.
	if lines.is_empty():
		return 0
	for line_index: int in range(lines.size()):
		var raw_line: Variant = lines[line_index]
		if raw_line is not Dictionary:
			continue
		var line: Dictionary = raw_line as Dictionary
		var line_start: int = int(line.get("start", 0))
		var line_length: int = maxi(0, int(line.get("length", str(line.get("text", "")).length())))
		var line_end: int = line_start + line_length
		if line_index + 1 < lines.size():
			var next_raw: Variant = lines[line_index + 1]
			if next_raw is Dictionary:
				var next_start: int = int((next_raw as Dictionary).get("start", line_end))
				if character_offset >= next_start:
					continue
				if character_offset > line_end:
					return line_index + 1
		if character_offset >= line_start:
			return line_index
	return 0


func _handle_wheel(event: InputEventMouseButton) -> bool:
	var is_vertical: bool = event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN
	var is_horizontal: bool = event.button_index == MOUSE_BUTTON_WHEEL_LEFT or event.button_index == MOUSE_BUTTON_WHEEL_RIGHT
	if not is_vertical and not is_horizontal:
		return false
	var factor: float = absf(event.factor)
	if factor <= 0.0001:
		factor = 1.0
	var modifier_zoom: bool = event.ctrl_pressed or event.meta_pressed
	if _input_mode == AppSettingsStore.InputMode.MOUSE or modifier_zoom:
		if not is_vertical:
			return false
		var direction: float = 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
		var zoom_factor: float = pow(MOUSE_ZOOM_STEP, direction * factor * _zoom_sensitivity)
		set_zoom(_target_zoom * zoom_factor, event.position)
		return true
	var screen_delta: Vector2 = Vector2.ZERO
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			screen_delta.y = TRACKPAD_WHEEL_PAN_PIXELS * factor
		MOUSE_BUTTON_WHEEL_DOWN:
			screen_delta.y = -TRACKPAD_WHEEL_PAN_PIXELS * factor
		MOUSE_BUTTON_WHEEL_LEFT:
			screen_delta.x = TRACKPAD_WHEEL_PAN_PIXELS * factor
		MOUSE_BUTTON_WHEEL_RIGHT:
			screen_delta.x = -TRACKPAD_WHEEL_PAN_PIXELS * factor
	_pan_by_screen_delta(screen_delta * _camera_sensitivity)
	return true


func _pan_by_screen_delta(screen_delta: Vector2) -> void:
	if screen_delta.is_zero_approx():
		return
	_set_context_ui_suppressed(true)
	_target_camera_position -= screen_delta / maxf(_target_zoom, 0.001)
	_mark_interaction()
	_mark_view_dirty()


func _draw() -> void:
	_draw_module_cards()
	_draw_hover_overlay()
	_draw_transient_connectors()
	_draw_commit_handoff_overlays()
	_draw_editor_selection_overlay()
	_draw_selection_overlay()
	_draw_editor_caret_overlay()
	_draw_pointer_preview()


func _draw_commit_handoff_overlays() -> void:
	# Stroke handoffs are retained under BoardWorld by StrokeHandoffRenderer. Only
	# text still needs this screen-space bridge because its editor/layout handoff
	# is tied to pixel-space typography.
	if _runtime == null or _text_commit_handoff_ids.is_empty():
		return
	var handoff_ids: Array[int] = []
	for raw_id: Variant in _text_commit_handoff_ids.keys():
		var entity_id: int = int(raw_id)
		if entity_id == _editing_entity_id or _hidden_render_ids.has(entity_id):
			continue
		if _runtime.model.text_blocks.contains(entity_id):
			handoff_ids.append(entity_id)
	if handoff_ids.is_empty():
		return
	handoff_ids.sort_custom(_sort_by_z_order)
	for entity_id: int in handoff_ids:
		_draw_transient_entity(entity_id)


func _draw_hover_overlay() -> void:
	if _runtime == null or _hover_entity_id <= 0 or _runtime.selection.contains(_hover_entity_id):
		return
	if not _runtime.model.contains(_hover_entity_id):
		return
	if _runtime.model.get_entity_type(_hover_entity_id) == BoardEntityTypes.CONNECTOR:
		_draw_connector_highlight(_hover_entity_id, Color(NotLightTheme.semantic_color("accent"), 0.58), 4.8)
		return
	var bounds: Rect2 = _runtime.model.get_entity_bounds(_hover_entity_id)
	var screen_rect: Rect2 = Rect2(world_to_screen(bounds.position), bounds.size * zoom)
	_draw_dashed_rect(screen_rect.grow(2.0), Color(NotLightTheme.semantic_color("accent"), 0.55), 5.0, 4.0, 1.2)


func _draw_selection_overlay() -> void:
	if _runtime == null:
		return
	var selected_ids: PackedInt64Array = _runtime.selection.get_selected_ids()
	var outline_color: Color = Color(NotLightTheme.semantic_color("accent"), 0.96)
	for entity_id: int in selected_ids:
		if not _runtime.model.contains(entity_id):
			continue
		if _runtime.model.get_entity_type(entity_id) == BoardEntityTypes.CONNECTOR:
			if entity_id != _connector_edit_entity_id:
				_draw_connector_highlight(entity_id, outline_color, 5.4)
			continue
		if entity_id == _editing_entity_id or _hidden_render_ids.has(entity_id):
			_draw_transient_entity(entity_id)
		var world_bounds: Rect2 = _editing_preview_bounds if entity_id == _editing_entity_id else _runtime.model.get_entity_bounds(entity_id)
		var screen_rect: Rect2 = Rect2(world_to_screen(world_bounds.position), world_bounds.size * zoom)
		draw_rect(screen_rect.grow(1.0), outline_color, false, 1.7, true)
		if _runtime.model.get_entity_type(entity_id) == BoardEntityTypes.TEXT and entity_id != _editing_entity_id:
			_draw_empty_text_hint(entity_id, screen_rect)
	if selected_ids.size() == 1 and _editing_entity_id == 0:
		var primary_id: int = _runtime.selection.primary_id
		if primary_id > 0 and _runtime.model.contains(primary_id):
			if _runtime.model.get_entity_type(primary_id) == BoardEntityTypes.CONNECTOR:
				_draw_connector_edit_handles(primary_id)
			else:
				var primary_bounds: Rect2 = _runtime.model.get_entity_bounds(primary_id)
				var primary_screen_rect: Rect2 = Rect2(world_to_screen(primary_bounds.position), primary_bounds.size * zoom)
				_draw_resize_handles(primary_screen_rect)
				_draw_connection_handles(primary_id, primary_screen_rect, false)


func _draw_empty_text_hint(entity_id: int, screen_rect: Rect2) -> void:
	if _runtime == null or zoom < 0.48:
		return
	if not _runtime.model.text_blocks.get_text(entity_id).is_empty():
		return
	var record: Dictionary = _runtime.model.text_blocks.get_record(entity_id)
	if _record_has_visible_list_marker(record):
		return
	var editing: bool = entity_id == _editing_entity_id
	if not editing and _hidden_render_ids.has(entity_id):
		return
	var hint_text: String = NotLightL10n.text("runtime.board.native_board_view.841c787a44") if editing else NotLightL10n.text("runtime.board.native_board_view.070f4d88e7")
	var hint_font_size: int = clampi(int(round((TextBlockStore.DEFAULT_FONT_SIZE if editing else 14.0) * zoom)), 11, 64)
	draw_string(
		_overlay_font,
		screen_rect.position + Vector2(7.0 * zoom, 5.0 * zoom + hint_font_size),
		hint_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		maxf(1.0, screen_rect.size.x - 14.0 * zoom),
		hint_font_size,
		Color(NotLightTheme.semantic_color("text_muted"), 0.62 if editing else 0.82)
	)


func _draw_resize_handles(screen_rect: Rect2) -> void:
	var handle_color: Color = Color("#fffef9")
	var border_color: Color = NotLightTheme.semantic_color("accent")
	for point: Vector2 in _corner_handle_points(screen_rect):
		draw_circle(point, HANDLE_SIZE * 0.55, handle_color)
		draw_circle(point, HANDLE_SIZE * 0.55, border_color, false, 1.8, true)


func _draw_connection_handles(entity_id: int, screen_rect: Rect2, target_state: bool) -> void:
	if _runtime == null or entity_id <= 0:
		return
	var fill: Color = Color("#8fe0ad") if not target_state else Color("#b7f2c9")
	var border: Color = Color("#268653")
	for point: Vector2 in _connection_handle_screen_points(screen_rect):
		draw_circle(point, 5.0 if not target_state else 6.0, fill)
		draw_circle(point, 5.0 if not target_state else 6.0, border, false, 1.5, true)


func _draw_pointer_preview() -> void:
	if _pointer_action == ACTION_DRAW_STROKE and not _active_stroke_preview.is_empty():
		var preview_limit: int = _runtime.render_policy.spray_preview_particles if _runtime != null else 80
		var source_points: PackedVector2Array = _active_stroke_preview
		if _drawing_style_id == StrokeStore.STYLE_SPRAY:
			source_points = _sample_stroke_preview_points(source_points, maxi(24, int(preview_limit / 2)))
		var screen_points: PackedVector2Array = PackedVector2Array()
		screen_points.resize(source_points.size())
		for index: int in range(source_points.size()):
			screen_points[index] = world_to_screen(source_points[index])
		StrokeBatchRenderer.draw_stroke(self, screen_points, _drawing_style_id, _drawing_color, _drawing_width * zoom, 0, _drawing_spray_spread, preview_limit)
	elif _active_tool_id == BoardToolController.TOOL_DRAW and _drawing_eraser_enabled:
		draw_circle(_pointer_current_screen, _drawing_eraser_radius * zoom, Color(NotLightTheme.semantic_color("accent"), 0.08), true, -1.0, true)
		draw_circle(_pointer_current_screen, _drawing_eraser_radius * zoom, Color(NotLightTheme.semantic_color("accent"), 0.85), false, 1.4, true)
	if _pointer_action == ACTION_MARQUEE and _action_started:
		var marquee_rect: Rect2 = Rect2(_pointer_start_screen, _pointer_current_screen - _pointer_start_screen).abs()
		draw_rect(marquee_rect, Color(NotLightTheme.semantic_color("accent"), 0.07), true)
		_draw_dashed_rect(marquee_rect, Color(NotLightTheme.semantic_color("accent"), 0.78), 7.0, 5.0, 1.4)
	elif _pointer_action == ACTION_CREATE_TEXT:
		var screen_rect: Rect2
		if _action_started:
			screen_rect = Rect2(_pointer_start_screen, _pointer_current_screen - _pointer_start_screen).abs()
		else:
			screen_rect = Rect2(_pointer_start_screen, DEFAULT_TEXT_SIZE * zoom)
		_draw_dashed_rect(screen_rect, Color(NotLightTheme.semantic_color("accent"), 0.88), 7.0, 5.0, 1.6)
	elif _pointer_action == ACTION_CONNECT and _runtime != null and _connection_source_entity_id > 0:
		var source_bounds: Rect2 = _runtime.model.get_entity_bounds(_connection_source_entity_id)
		var start_world: Vector2 = ConnectorGeometry.anchor_position(source_bounds, _connection_source_anchor)
		var finish_world: Vector2 = _pointer_current_world
		var finish_anchor: int = (_connection_source_anchor + 2) % ConnectorGeometry.ANCHOR_COUNT
		if _connection_target_entity_id > 0 and _runtime.model.contains(_connection_target_entity_id):
			var target_bounds: Rect2 = _runtime.model.get_entity_bounds(_connection_target_entity_id)
			finish_world = ConnectorGeometry.anchor_position(target_bounds, _connection_target_anchor)
			finish_anchor = _connection_target_anchor
			var target_screen: Rect2 = Rect2(world_to_screen(target_bounds.position), target_bounds.size * zoom)
			_draw_connection_handles(_connection_target_entity_id, target_screen, true)
		_draw_curve_in_screen(start_world, _connection_source_anchor, finish_world, finish_anchor, Color("#2f8f5b"), 2.4)
	elif _pointer_action == ACTION_REWIRE_CONNECTOR or _pointer_action == ACTION_MOVE_ROUTER_POINT:
		_draw_connector_edit_preview()


func _draw_transient_entity(entity_id: int) -> void:
	if _runtime == null or not _runtime.model.contains(entity_id):
		return
	var type_id: StringName = _runtime.model.get_entity_type(entity_id)
	if type_id == BoardEntityTypes.TEXT:
		_draw_transient_text_block(entity_id)
	elif type_id == BoardEntityTypes.IMAGE:
		_draw_transient_image(entity_id)
	elif type_id == BoardEntityTypes.VIDEO:
		_draw_transient_video(entity_id)
	elif type_id == BoardEntityTypes.AUDIO:
		_draw_transient_audio(entity_id)
	elif type_id == BoardEntityTypes.FORMULA:
		_draw_transient_formula(entity_id)
	elif type_id == BoardEntityTypes.MODULE:
		_draw_module_card(entity_id, true)
	elif type_id == BoardEntityTypes.NOTE_PORTAL:
		_draw_transient_note_portal(entity_id)
	elif type_id == BoardEntityTypes.STROKE:
		_draw_transient_stroke(entity_id)



func _draw_transient_note_portal(entity_id: int) -> void:
	if _runtime == null or not _runtime.model.note_portals.contains(entity_id):
		return
	var bounds: Rect2 = _runtime.model.get_entity_bounds(entity_id)
	var screen_rect: Rect2 = Rect2(world_to_screen(bounds.position), bounds.size * zoom)
	var note_id: String = _runtime.model.note_portals.get_note_id(entity_id)
	var note: Dictionary = _note_repository.get_note(note_id) if _note_repository != null else {}
	var missing: bool = note.is_empty()
	var surface: Color = NotLightTheme.semantic_color("surface")
	var border: Color = NotLightTheme.semantic_color("danger") if missing else NotLightTheme.semantic_color("border_strong")
	var accent: Color = NotLightTheme.semantic_color("danger") if missing else NotLightTheme.semantic_color("accent")
	draw_rect(screen_rect, surface, true)
	draw_rect(screen_rect, border, false, 1.6, true)
	draw_rect(Rect2(screen_rect.position, Vector2(maxf(3.0, 6.0 * zoom), screen_rect.size.y)), accent, true)
	if screen_rect.size.x < 80.0 or screen_rect.size.y < 48.0:
		return
	var title: String = NotLightL10n.text("notes.portal.missing") if missing else str(note.get("display_name", NotLightL10n.text("notes.untitled")))
	var font_size: int = clampi(int(round(18.0 * zoom)), 10, 28)
	var left: float = screen_rect.position.x + maxf(12.0, 20.0 * zoom)
	draw_string(ThemeDB.fallback_font, Vector2(left, screen_rect.position.y + maxf(25.0, 34.0 * zoom)), title, HORIZONTAL_ALIGNMENT_LEFT, maxf(1.0, screen_rect.end.x - left - 12.0), font_size, NotLightTheme.semantic_color("text"))


func _draw_module_cards() -> void:
	if _runtime == null or _runtime.model.modules.size() <= 0:
		return
	var visible_world: Rect2 = _target_visible_world_rect().grow(160.0 / maxf(zoom, 0.001))
	var ordered: Array[int] = []
	for entity_id: int in _runtime.model.modules.entity_ids:
		if not _runtime.model.contains(entity_id):
			continue
		if not _runtime.model.get_entity_bounds(entity_id).intersects(visible_world, true):
			continue
		ordered.append(entity_id)
	ordered.sort_custom(_sort_by_z_order)
	for entity_id: int in ordered:
		if _hidden_render_ids.has(entity_id) or _live_module_surface_ids.has(entity_id):
			continue
		_draw_module_card(entity_id, false)


func _draw_module_card(entity_id: int, transient: bool) -> void:
	if _runtime == null or not _runtime.model.modules.contains(entity_id):
		return
	if _live_module_surface_ids.has(entity_id):
		return
	var bounds: Rect2 = _runtime.model.get_entity_bounds(entity_id)
	var screen_rect: Rect2 = Rect2(world_to_screen(bounds.position), bounds.size * zoom)
	if screen_rect.size.x < 3.0 or screen_rect.size.y < 3.0:
		return
	var module_id: String = _runtime.model.modules.get_module_id(entity_id)
	var installed: bool = _module_registry != null and _module_registry.is_module_active(module_id)
	var manifest: Dictionary = _module_registry.get_active_manifest(module_id) if installed else {}
	var title: String = _runtime.model.modules.get_instance_title(entity_id)
	if title.is_empty():
		title = str(manifest.get("name", module_id))
	var surface_color: Color = NotLightTheme.semantic_color("surface")
	var border_color: Color = NotLightTheme.semantic_color("border_strong") if installed else Color(NotLightTheme.semantic_color("danger"), 0.72)
	if transient:
		surface_color.a = 0.92
	draw_rect(screen_rect, surface_color, true)
	draw_rect(screen_rect, border_color, false, maxf(1.0, minf(1.6, zoom * 1.2)), true)
	var strip_height: float = minf(screen_rect.size.y, maxf(3.0, 5.0 * zoom))
	draw_rect(Rect2(screen_rect.position, Vector2(screen_rect.size.x, strip_height)), NotLightTheme.semantic_color("accent") if installed else NotLightTheme.semantic_color("danger"), true)
	if screen_rect.size.x < 84.0 or screen_rect.size.y < 56.0:
		return
	var font: Font = _overlay_font if _overlay_font != null else ThemeDB.fallback_font
	var title_size: int = clampi(int(round(17.0 * zoom)), 11, 24)
	var body_size: int = clampi(int(round(12.0 * zoom)), 9, 17)
	var left: float = screen_rect.position.x + maxf(10.0, 14.0 * zoom)
	var top: float = screen_rect.position.y + maxf(22.0, 30.0 * zoom)
	var available: float = maxf(1.0, screen_rect.size.x - maxf(20.0, 28.0 * zoom))
	draw_string(font, Vector2(left, top), title, HORIZONTAL_ALIGNMENT_LEFT, available, title_size, NotLightTheme.semantic_color("text"))
	var status: String = NotLightL10n.text("modules.board.double_click") if installed else NotLightL10n.text("modules.board.missing_short")
	draw_string(font, Vector2(left, top + maxf(18.0, 25.0 * zoom)), status, HORIZONTAL_ALIGNMENT_LEFT, available, body_size, NotLightTheme.semantic_color("text_muted") if installed else NotLightTheme.semantic_color("danger"))
	if screen_rect.size.y >= 104.0:
		draw_string(font, Vector2(left, top + maxf(36.0, 47.0 * zoom)), module_id, HORIZONTAL_ALIGNMENT_LEFT, available, maxi(9, body_size - 1), Color(NotLightTheme.semantic_color("text_muted"), 0.78))


func _draw_transient_formula(entity_id: int) -> void:
	if _runtime == null or not _runtime.model.formulas.contains(entity_id):
		return
	var bounds: Rect2 = _runtime.model.get_entity_bounds(entity_id)
	var screen_rect: Rect2 = Rect2(world_to_screen(bounds.position), bounds.size * zoom)
	var record: Dictionary = _runtime.model.formulas.get_record(entity_id)
	var desired_extent: float = maxf(screen_rect.size.x, screen_rect.size.y)
	var texture: Texture2D = _formula_render.request_texture(record, desired_extent) if _formula_render != null else null
	if texture != null:
		var source_size: Vector2 = texture.get_size()
		if source_size.x > 0.0 and source_size.y > 0.0:
			var inner: Rect2 = screen_rect.grow(-7.0)
			var scale_value: float = minf(inner.size.x / source_size.x, inner.size.y / source_size.y)
			var fitted_size: Vector2 = source_size * scale_value
			var foreground: Color = _runtime.model.formulas.get_foreground(entity_id)
			foreground.a = 1.0
			draw_texture_rect(texture, Rect2(inner.get_center() - fitted_size * 0.5, fitted_size), false, foreground)
	else:
		var font: Font = ThemeDB.fallback_font
		var label: String = "fx"
		var text_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20)
		draw_string(font, screen_rect.get_center() + Vector2(-text_size.x * 0.5, text_size.y * 0.25), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, NotLightTheme.semantic_color("accent"))
	draw_rect(screen_rect, Color("#aeb9a9"), false, 1.15)


func _draw_transient_audio(entity_id: int) -> void:
	if _runtime == null or not _runtime.model.audios.contains(entity_id):
		return
	var bounds: Rect2 = _runtime.model.get_entity_bounds(entity_id)
	var screen_rect: Rect2 = Rect2(world_to_screen(bounds.position), bounds.size * zoom)
	draw_rect(screen_rect, Color("#f3f3ed"), true)
	draw_rect(screen_rect, Color(0.16, 0.42, 0.31, 0.48), false, 1.5)
	var center: Vector2 = Vector2(screen_rect.position.x + minf(screen_rect.size.y * 0.50, 38.0), screen_rect.get_center().y)
	var radius: float = minf(minf(screen_rect.size.y, screen_rect.size.x) * 0.28, 24.0)
	if radius > 2.0:
		draw_circle(center, radius, NotLightTheme.semantic_color("accent"))
		var tri: float = radius * 0.78
		var triangle_color: Color = Color("#fbfcf8")
		draw_primitive(
			PackedVector2Array([
				center + Vector2(-tri * 0.24, -tri * 0.46),
				center + Vector2(-tri * 0.24, tri * 0.46),
				center + Vector2(tri * 0.56, 0.0),
			]),
			PackedColorArray([triangle_color, triangle_color, triangle_color]),
			PackedVector2Array()
		)
	var asset_id: String = _runtime.model.audios.get_asset_id(entity_id)
	var texture: Texture2D = _audio_media.get_waveform(asset_id) if _audio_media != null else null
	if texture != null and screen_rect.size.x > 60.0:
		var wave_rect: Rect2 = Rect2(Vector2(center.x + radius + 8.0, screen_rect.position.y + screen_rect.size.y * 0.22), Vector2(maxf(1.0, screen_rect.end.x - center.x - radius - 16.0), screen_rect.size.y * 0.56))
		draw_texture_rect(texture, wave_rect, false, Color(0.16, 0.48, 0.35, 0.82))


func _draw_transient_stroke(entity_id: int) -> void:
	if _runtime == null or not _runtime.model.strokes.contains(entity_id):
		return
	var bounds: Rect2 = _runtime.model.get_entity_bounds(entity_id)
	var style_id: int = _runtime.model.strokes.get_style_id(entity_id)
	var preview_limit: int = _runtime.render_policy.spray_preview_particles
	var world_points: PackedVector2Array
	if style_id == StrokeStore.STYLE_SPRAY:
		# Do not materialize every point of a long spray while dragging it. The
		# settled renderer uses a cached GPU MultiMesh; this light proxy keeps
		# interaction responsive and preserves the overall path silhouette.
		var local_points: PackedVector2Array = _runtime.model.strokes.get_local_points(entity_id)
		var sampled: PackedVector2Array = _sample_stroke_preview_points(local_points, maxi(24, int(preview_limit / 2)))
		world_points = StrokeGeometry.transformed_points(sampled, _runtime.model.strokes.get_original_size(entity_id), bounds)
	else:
		world_points = _runtime.model.strokes.get_world_points(entity_id, bounds)
	var screen_points: PackedVector2Array = PackedVector2Array()
	screen_points.resize(world_points.size())
	for index: int in range(world_points.size()):
		screen_points[index] = world_to_screen(world_points[index])
	StrokeBatchRenderer.draw_stroke(
		self,
		screen_points,
		style_id,
		_runtime.model.strokes.get_color(entity_id),
		_runtime.model.strokes.get_effective_width(entity_id, bounds) * zoom,
		entity_id,
		_runtime.model.strokes.get_spray_spread(entity_id),
		preview_limit
	)


func _sample_stroke_preview_points(points: PackedVector2Array, maximum_points: int) -> PackedVector2Array:
	if points.size() <= maximum_points or maximum_points < 3:
		return points
	var result: PackedVector2Array = PackedVector2Array()
	var stride: int = maxi(1, int(ceil(float(points.size() - 1) / float(maximum_points - 1))))
	for index: int in range(0, points.size(), stride):
		result.append(points[index])
	if result.is_empty() or result[result.size() - 1] != points[points.size() - 1]:
		result.append(points[points.size() - 1])
	return result


func _draw_transient_video(entity_id: int) -> void:
	if _runtime == null or not _runtime.model.videos.contains(entity_id):
		return
	var bounds: Rect2 = _runtime.model.get_entity_bounds(entity_id)
	var screen_rect: Rect2 = Rect2(world_to_screen(bounds.position), bounds.size * zoom)
	var asset_id: String = _runtime.model.videos.get_asset_id(entity_id)
	var texture: Texture2D = _video_media.get_thumbnail(asset_id) if _video_media != null else null
	draw_rect(screen_rect, Color("#202623"), true)
	if texture != null:
		var texture_size: Vector2 = texture.get_size()
		if texture_size.x > 0.0 and texture_size.y > 0.0:
			var scale_value: float = minf(screen_rect.size.x / texture_size.x, screen_rect.size.y / texture_size.y)
			var fitted: Vector2 = texture_size * scale_value
			var target: Rect2 = Rect2(screen_rect.get_center() - fitted * 0.5, fitted)
			draw_texture_rect(texture, target, false)
	var radius: float = clampf(minf(screen_rect.size.x, screen_rect.size.y) * 0.09, 12.0, 34.0)
	var center: Vector2 = screen_rect.get_center()
	draw_circle(center, radius, Color(0.96, 0.98, 0.95, 0.92))
	var triangle_size: float = radius * 0.80
	var triangle: PackedVector2Array = PackedVector2Array([
		center + Vector2(-triangle_size * 0.28, -triangle_size * 0.50),
		center + Vector2(-triangle_size * 0.28, triangle_size * 0.50),
		center + Vector2(triangle_size * 0.58, 0.0),
	])
	var triangle_color: Color = NotLightTheme.semantic_color("accent")
	draw_primitive(
		triangle,
		PackedColorArray([triangle_color, triangle_color, triangle_color]),
		PackedVector2Array()
	)


func _draw_transient_image(entity_id: int) -> void:
	if _runtime == null or not _runtime.model.images.contains(entity_id):
		return
	var bounds: Rect2 = _runtime.model.get_entity_bounds(entity_id)
	var screen_rect: Rect2 = Rect2(world_to_screen(bounds.position), bounds.size * zoom)
	var asset_id: String = _runtime.model.images.get_asset_id(entity_id)
	var texture: Texture2D = null
	if _image_cache != null:
		texture = _image_cache.request_texture(asset_id, maxf(screen_rect.size.x, screen_rect.size.y))
	if texture != null:
		draw_texture_rect(texture, screen_rect, false)
	else:
		draw_rect(screen_rect, Color("#edf2ea"), true)
		draw_rect(screen_rect, Color("#9faf9f"), false, 1.2, true)
		draw_line(screen_rect.position, screen_rect.end, Color("#9faf9f"), 1.0, true)
		draw_line(Vector2(screen_rect.end.x, screen_rect.position.y), Vector2(screen_rect.position.x, screen_rect.end.y), Color("#9faf9f"), 1.0, true)


func _draw_transient_text_block(entity_id: int) -> void:
	if _runtime == null or _runtime.model.get_entity_type(entity_id) != BoardEntityTypes.TEXT:
		return
	var bounds: Rect2 = _editing_preview_bounds if entity_id == _editing_entity_id else _runtime.model.get_entity_bounds(entity_id)
	var screen_rect: Rect2 = Rect2(world_to_screen(bounds.position), bounds.size * zoom)
	var record: Dictionary = _runtime.model.text_blocks.get_record(entity_id)
	var background: Color = _runtime.model.text_blocks.get_background_color(entity_id)
	if background.a > 0.001:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = background
		style.border_color = background.darkened(0.14)
		style.set_border_width_all(1)
		style.set_corner_radius_all(clampi(int(round(12.0 * zoom)), 5, 14))
		draw_style_box(style, screen_rect)
	var text: String = str(record.get("text", ""))
	if text.is_empty() and not _record_has_visible_list_marker(record):
		_draw_empty_text_hint(entity_id, screen_rect)
		return
	_draw_rich_text_record_screen(record, screen_rect, zoom)


func _record_has_visible_list_marker(record: Dictionary) -> bool:
	var paragraphs: Array = record.get("paragraphs", []) as Array
	if paragraphs.is_empty() or paragraphs[0] is not Dictionary:
		return false
	return int((paragraphs[0] as Dictionary).get("list_type", TextBlockStore.LIST_NONE)) != TextBlockStore.LIST_NONE


func _build_rich_text_screen_layout(record: Dictionary, screen_rect: Rect2, scale_factor: float) -> Dictionary:
	var text: String = str(record.get("text", ""))
	if text.is_empty() and not _record_has_visible_list_marker(record):
		return {}
	var world_font_size: float = float(record.get("font_size", TextBlockStore.DEFAULT_FONT_SIZE))
	var screen_font_size: float = maxf(10.0, world_font_size * scale_factor)
	var font_size: int = clampi(int(round(screen_font_size)), 10, 512)
	var family: String = str(record.get("font_family", TextBlockStore.DEFAULT_FONT_FAMILY))
	var background: Color = Color.from_string(
		str(record.get("background_color", Color.TRANSPARENT.to_html(true))),
		Color.TRANSPARENT
	)
	var padding: Vector2 = TextLayoutUtils.padding_for_background(background) * scale_factor
	var available_width: float = maxf(12.0, screen_rect.size.x - padding.x * 2.0)
	var paragraphs: Array = record.get("paragraphs", []) as Array
	var runs: Array = record.get("style_runs", []) as Array
	var base_flags: int = int(record.get("base_style_flags", 0))
	var base_color: Color = Color.from_string(
		str(record.get("text_color", TextBlockStore.COLOR_TEXT.to_html(true))),
		TextBlockStore.COLOR_TEXT
	)
	var wrapped: Dictionary = TextLayoutUtils.wrap_text_rich(
		text,
		available_width,
		screen_font_size,
		paragraphs,
		256,
		runs,
		base_flags
	)
	var lines: PackedStringArray = wrapped.get("lines", PackedStringArray()) as PackedStringArray
	var starts: PackedInt32Array = wrapped.get("starts", PackedInt32Array()) as PackedInt32Array
	var lengths: PackedInt32Array = wrapped.get("lengths", PackedInt32Array()) as PackedInt32Array
	var prefixes: PackedStringArray = wrapped.get("prefixes", PackedStringArray()) as PackedStringArray
	var indents: PackedFloat32Array = wrapped.get("indents", PackedFloat32Array()) as PackedFloat32Array
	var alignment: HorizontalAlignment = clampi(
		int(record.get("alignment", HORIZONTAL_ALIGNMENT_LEFT)),
		HORIZONTAL_ALIGNMENT_LEFT,
		HORIZONTAL_ALIGNMENT_RIGHT
	) as HorizontalAlignment
	var baseline_y: float = screen_rect.position.y + padding.y + screen_font_size
	var line_layouts: Array[Dictionary] = []
	line_layouts.resize(lines.size())
	for line_index: int in range(lines.size()):
		var line_text: String = lines[line_index]
		var line_start: int = int(starts[line_index]) if line_index < starts.size() else 0
		var line_length: int = int(lengths[line_index]) if line_index < lengths.size() else line_text.length()
		var prefix: String = prefixes[line_index] if line_index < prefixes.size() else ""
		var indent: float = float(indents[line_index]) if line_index < indents.size() else 0.0
		var spans: Array[Dictionary] = _rich_spans_for_line(
			line_text,
			line_start,
			line_length,
			runs,
			base_flags,
			base_color
		)
		var content_width: float = _rich_span_width(spans, family, font_size)
		var prefix_flags: int = int(spans[0].get("flags", base_flags)) if not spans.is_empty() else base_flags
		var prefix_color: Color = base_color
		if not spans.is_empty():
			prefix_color = spans[0].get("color", base_color) as Color
		var prefix_font: Font = _font_registry.get_font(family, prefix_flags)
		var prefix_width: float = (
			prefix_font.get_string_size(prefix, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
			if not prefix.is_empty()
			else 0.0
		)
		var gap: float = screen_font_size * TextLayoutUtils.LIST_MARKER_GAP_FACTOR if not prefix.is_empty() else 0.0
		var base_indent: float = maxf(0.0, indent - prefix_width - gap) if not prefix.is_empty() else indent
		var group_width: float = (
			base_indent + prefix_width + gap + content_width
			if not prefix.is_empty()
			else indent + content_width
		)
		var align_offset: float = 0.0
		if alignment == HORIZONTAL_ALIGNMENT_CENTER:
			align_offset = maxf(0.0, (available_width - group_width) * 0.5)
		elif alignment == HORIZONTAL_ALIGNMENT_RIGHT:
			align_offset = maxf(0.0, available_width - group_width)
		var prefix_x: float = screen_rect.position.x + padding.x + align_offset + base_indent
		var content_x: float = prefix_x + prefix_width + gap if not prefix.is_empty() else prefix_x
		line_layouts[line_index] = {
			"text": line_text,
			"start": line_start,
			"length": line_length,
			"prefix": prefix,
			"prefix_x": prefix_x,
			"content_x": content_x,
			"baseline_y": baseline_y,
			"spans": spans,
			"prefix_font": prefix_font,
			"prefix_color": prefix_color,
		}
		baseline_y += TextLayoutUtils.line_height(screen_font_size)
	return {
		"family": family,
		"font_size": font_size,
		"screen_font_size": screen_font_size,
		"base_flags": base_flags,
		"base_color": base_color,
		"runs": runs,
		"lines": line_layouts,
	}


func _draw_rich_text_record_screen(record: Dictionary, screen_rect: Rect2, scale_factor: float) -> void:
	var layout: Dictionary = _build_rich_text_screen_layout(record, screen_rect, scale_factor)
	if layout.is_empty():
		return
	var family: String = str(layout.get("family", TextBlockStore.DEFAULT_FONT_FAMILY))
	var font_size: int = int(layout.get("font_size", 12))
	var line_layouts: Array = layout.get("lines", []) as Array
	for raw_line: Variant in line_layouts:
		if raw_line is not Dictionary:
			continue
		var line: Dictionary = raw_line as Dictionary
		var prefix: String = str(line.get("prefix", ""))
		var baseline_y: float = float(line.get("baseline_y", 0.0))
		if not prefix.is_empty():
			var prefix_font: Font = line.get("prefix_font", _font_registry.get_font(family, 0)) as Font
			var prefix_color: Color = line.get("prefix_color", TextBlockStore.COLOR_TEXT) as Color
			draw_string(
				prefix_font,
				Vector2(float(line.get("prefix_x", 0.0)), baseline_y),
				prefix,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1.0,
				font_size,
				prefix_color
			)
		var spans: Array[Dictionary] = []
		var raw_spans: Variant = line.get("spans", [])
		if raw_spans is Array:
			for raw_span: Variant in raw_spans as Array:
				if raw_span is Dictionary:
					spans.append(raw_span as Dictionary)
		_draw_rich_spans(
			spans,
			family,
			font_size,
			Vector2(float(line.get("content_x", 0.0)), baseline_y)
		)


func _rich_spans_for_line(
	line_text: String,
	line_start: int,
	line_length: int,
	runs: Array,
	base_flags: int,
	base_color: Color
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if line_text.is_empty():
		return result
	var source_length: int = mini(line_length, line_text.length())
	var line_end: int = line_start + source_length
	var cursor: int = line_start
	for raw_run: Variant in runs:
		if raw_run is not Dictionary:
			continue
		var run: Dictionary = raw_run as Dictionary
		var run_start: int = int(run.get("start", 0))
		var run_end: int = run_start + int(run.get("length", 0))
		if run_end <= line_start or run_start >= line_end:
			continue
		var segment_start: int = maxi(cursor, maxi(line_start, run_start))
		if segment_start > cursor:
			_rich_append_span(result, line_text.substr(cursor - line_start, segment_start - cursor), base_flags, base_color)
		var segment_end: int = mini(line_end, run_end)
		if segment_end > segment_start:
			_rich_append_span(
				result,
				line_text.substr(segment_start - line_start, segment_end - segment_start),
				int(run.get("flags", base_flags)),
				Color.from_string(str(run.get("color", base_color.to_html(true))), base_color)
			)
			cursor = segment_end
	if cursor < line_end:
		_rich_append_span(result, line_text.substr(cursor - line_start, line_end - cursor), base_flags, base_color)
	if line_text.length() > source_length:
		var suffix_flags: int = int(result[result.size() - 1].get("flags", base_flags)) if not result.is_empty() else base_flags
		var suffix_color: Color = base_color
		if not result.is_empty():
			suffix_color = result[result.size() - 1].get("color", base_color) as Color
		_rich_append_span(result, line_text.substr(source_length), suffix_flags, suffix_color)
	if result.is_empty():
		_rich_append_span(result, line_text, base_flags, base_color)
	return result


func _rich_append_span(result: Array[Dictionary], text: String, flags: int, color: Color) -> void:
	if text.is_empty():
		return
	if not result.is_empty():
		var previous: Dictionary = result[result.size() - 1]
		if int(previous.get("flags", 0)) == flags and (previous.get("color", Color.WHITE) as Color) == color:
			previous["text"] = str(previous.get("text", "")) + text
			return
	result.append({"text": text, "flags": flags, "color": color})


func _rich_span_width(spans: Array[Dictionary], family: String, font_size: int) -> float:
	var width: float = 0.0
	for span: Dictionary in spans:
		var font: Font = _font_registry.get_font(family, int(span.get("flags", 0)))
		width += font.get_string_size(str(span.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	return width


func _draw_rich_spans(spans: Array[Dictionary], family: String, font_size: int, start_position: Vector2) -> void:
	var x: float = start_position.x
	for span: Dictionary in spans:
		var text: String = str(span.get("text", ""))
		if text.is_empty():
			continue
		var flags: int = int(span.get("flags", 0))
		var color: Color = span.get("color", TextBlockStore.COLOR_TEXT) as Color
		var font: Font = _font_registry.get_font(family, flags)
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		draw_string(font, Vector2(x, start_position.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
		if (flags & TextBlockStore.FONT_STYLE_UNDERLINE) != 0:
			var underline_y: float = start_position.y + font.get_underline_position(font_size)
			draw_line(Vector2(x, underline_y), Vector2(x + width, underline_y), color, maxf(1.0, font.get_underline_thickness(font_size)), true)
		if (flags & TextBlockStore.FONT_STYLE_STRIKETHROUGH) != 0:
			var strike_y: float = start_position.y - font.get_ascent(font_size) * 0.34
			draw_line(Vector2(x, strike_y), Vector2(x + width, strike_y), color, maxf(1.0, font.get_underline_thickness(font_size)), true)
		x += width


func _draw_connector_highlight(entity_id: int, color: Color, width: float) -> void:
	if _runtime == null or not _runtime.model.connectors.contains(entity_id):
		return
	var source_id: int = _runtime.model.connectors.get_source_entity_id(entity_id)
	var target_id: int = _runtime.model.connectors.get_target_entity_id(entity_id)
	if not _runtime.model.contains(source_id) or not _runtime.model.contains(target_id):
		return
	var source_anchor: int = _runtime.model.connectors.get_source_anchor(entity_id)
	var target_anchor: int = _runtime.model.connectors.get_target_anchor(entity_id)
	var start: Vector2 = ConnectorGeometry.anchor_position(_runtime.model.get_entity_bounds(source_id), source_anchor)
	var finish: Vector2 = ConnectorGeometry.anchor_position(_runtime.model.get_entity_bounds(target_id), target_anchor)
	_draw_curve_in_screen(
		start,
		source_anchor,
		finish,
		target_anchor,
		color,
		width,
		_runtime.model.connectors.get_router_points(entity_id),
		_runtime.model.connectors.get_direction(entity_id)
	)


func _draw_transient_connectors() -> void:
	if _runtime == null or _hidden_connector_ids.is_empty():
		return
	for connector_key: Variant in _hidden_connector_ids.keys():
		var connector_id: int = int(connector_key)
		if connector_id == _connector_edit_entity_id:
			continue
		if not _runtime.model.connectors.contains(connector_id):
			continue
		var source_id: int = _runtime.model.connectors.get_source_entity_id(connector_id)
		var target_id: int = _runtime.model.connectors.get_target_entity_id(connector_id)
		if not _runtime.model.contains(source_id) or not _runtime.model.contains(target_id):
			continue
		var source_anchor: int = _runtime.model.connectors.get_source_anchor(connector_id)
		var target_anchor: int = _runtime.model.connectors.get_target_anchor(connector_id)
		var start: Vector2 = ConnectorGeometry.anchor_position(_runtime.model.get_entity_bounds(source_id), source_anchor)
		var finish: Vector2 = ConnectorGeometry.anchor_position(_runtime.model.get_entity_bounds(target_id), target_anchor)
		_draw_curve_in_screen(
			start,
			source_anchor,
			finish,
			target_anchor,
			_runtime.model.connectors.get_color(connector_id),
			_runtime.model.connectors.get_width(connector_id),
			_runtime.model.connectors.get_router_points(connector_id),
			_runtime.model.connectors.get_direction(connector_id)
		)


func _draw_curve_in_screen(
	start_world: Vector2,
	start_anchor: int,
	finish_world: Vector2,
	finish_anchor: int,
	color: Color,
	width: float,
	router_points: PackedVector2Array = PackedVector2Array(),
	direction_mode: int = ConnectorStore.DEFAULT_DIRECTION
) -> void:
	var world_points: PackedVector2Array = ConnectorGeometry.sample_routed_curve(
		start_world,
		start_anchor,
		finish_world,
		finish_anchor,
		router_points,
		zoom,
		240
	)
	var screen_points: PackedVector2Array = PackedVector2Array()
	screen_points.resize(world_points.size())
	for index: int in range(world_points.size()):
		screen_points[index] = world_to_screen(world_points[index])
	if screen_points.size() >= 2:
		draw_polyline(screen_points, color, width, true)
		if ConnectorGeometry.direction_has_source_arrow(direction_mode):
			_draw_arrowhead_screen(screen_points[0], screen_points[1], color, width)
		if ConnectorGeometry.direction_has_target_arrow(direction_mode):
			_draw_arrowhead_screen(
				screen_points[screen_points.size() - 1],
				screen_points[screen_points.size() - 2],
				color,
				width
			)


func _draw_arrowhead_screen(tip: Vector2, previous: Vector2, color: Color, width: float) -> void:
	var arrow_direction: Vector2 = (tip - previous).normalized()
	if arrow_direction.is_zero_approx():
		return
	var perpendicular: Vector2 = Vector2(-arrow_direction.y, arrow_direction.x)
	var base: Vector2 = tip - arrow_direction * 13.0
	draw_line(tip, base + perpendicular * 7.0, color, width, true)
	draw_line(tip, base - perpendicular * 7.0, color, width, true)


func _draw_connector_edit_handles(connector_id: int) -> void:
	if _runtime == null or not _runtime.model.connectors.contains(connector_id):
		return
	var source_id: int = _runtime.model.connectors.get_source_entity_id(connector_id)
	var target_id: int = _runtime.model.connectors.get_target_entity_id(connector_id)
	if not _runtime.model.contains(source_id) or not _runtime.model.contains(target_id):
		return
	var source_anchor: int = _runtime.model.connectors.get_source_anchor(connector_id)
	var target_anchor: int = _runtime.model.connectors.get_target_anchor(connector_id)
	var source_screen: Vector2 = world_to_screen(
		ConnectorGeometry.anchor_position(_runtime.model.get_entity_bounds(source_id), source_anchor)
	)
	var target_screen: Vector2 = world_to_screen(
		ConnectorGeometry.anchor_position(_runtime.model.get_entity_bounds(target_id), target_anchor)
	)
	var handle_fill: Color = Color("#a8e9bd")
	var handle_border: Color = Color("#238553")
	for point: Vector2 in PackedVector2Array([source_screen, target_screen]):
		draw_circle(point, CONNECTOR_EDIT_HANDLE_RADIUS, handle_fill)
		draw_circle(point, CONNECTOR_EDIT_HANDLE_RADIUS, handle_border, false, 1.8, true)
	for router_point: Vector2 in _runtime.model.connectors.get_router_points(connector_id):
		var screen_point: Vector2 = world_to_screen(router_point)
		draw_circle(screen_point, CONNECTOR_EDIT_HANDLE_RADIUS - 1.0, Color("#fffef9"))
		draw_circle(screen_point, CONNECTOR_EDIT_HANDLE_RADIUS - 1.0, handle_border, false, 1.8, true)


func _draw_connector_edit_preview() -> void:
	if _runtime == null or _connector_edit_entity_id <= 0 or not _runtime.model.connectors.contains(_connector_edit_entity_id):
		return
	var source_id: int = _runtime.model.connectors.get_source_entity_id(_connector_edit_entity_id)
	var target_id: int = _runtime.model.connectors.get_target_entity_id(_connector_edit_entity_id)
	var source_anchor: int = _runtime.model.connectors.get_source_anchor(_connector_edit_entity_id)
	var target_anchor: int = _runtime.model.connectors.get_target_anchor(_connector_edit_entity_id)
	var start: Vector2 = ConnectorGeometry.anchor_position(_runtime.model.get_entity_bounds(source_id), source_anchor)
	var finish: Vector2 = ConnectorGeometry.anchor_position(_runtime.model.get_entity_bounds(target_id), target_anchor)
	if _pointer_action == ACTION_REWIRE_CONNECTOR:
		if _connector_edit_endpoint == CONNECTOR_ENDPOINT_SOURCE:
			start = _pointer_current_world
			if _connector_edit_candidate_entity_id > 0 and _runtime.model.contains(_connector_edit_candidate_entity_id):
				source_anchor = _connector_edit_candidate_anchor
				start = ConnectorGeometry.anchor_position(
					_runtime.model.get_entity_bounds(_connector_edit_candidate_entity_id),
					source_anchor
				)
		else:
			finish = _pointer_current_world
			if _connector_edit_candidate_entity_id > 0 and _runtime.model.contains(_connector_edit_candidate_entity_id):
				target_anchor = _connector_edit_candidate_anchor
				finish = ConnectorGeometry.anchor_position(
					_runtime.model.get_entity_bounds(_connector_edit_candidate_entity_id),
					target_anchor
				)
	_draw_curve_in_screen(
		start,
		source_anchor,
		finish,
		target_anchor,
		_runtime.model.connectors.get_color(_connector_edit_entity_id),
		maxf(3.0, _runtime.model.connectors.get_width(_connector_edit_entity_id)),
		_connector_edit_preview_router_points,
		_runtime.model.connectors.get_direction(_connector_edit_entity_id)
	)
	if _connector_edit_candidate_entity_id > 0 and _runtime.model.contains(_connector_edit_candidate_entity_id):
		var target_bounds: Rect2 = _runtime.model.get_entity_bounds(_connector_edit_candidate_entity_id)
		var target_screen_rect: Rect2 = Rect2(world_to_screen(target_bounds.position), target_bounds.size * zoom)
		_draw_connection_handles(_connector_edit_candidate_entity_id, target_screen_rect, true)
	for router_point: Vector2 in _connector_edit_preview_router_points:
		var screen_point: Vector2 = world_to_screen(router_point)
		draw_circle(screen_point, CONNECTOR_EDIT_HANDLE_RADIUS - 1.0, Color("#fffef9"))
		draw_circle(screen_point, CONNECTOR_EDIT_HANDLE_RADIUS - 1.0, Color("#238553"), false, 1.8, true)


func _draw_dashed_rect(rect: Rect2, color: Color, dash: float, gap: float, width: float) -> void:
	_draw_dashed_segment(rect.position, Vector2(rect.end.x, rect.position.y), color, dash, gap, width)
	_draw_dashed_segment(Vector2(rect.end.x, rect.position.y), rect.end, color, dash, gap, width)
	_draw_dashed_segment(rect.end, Vector2(rect.position.x, rect.end.y), color, dash, gap, width)
	_draw_dashed_segment(Vector2(rect.position.x, rect.end.y), rect.position, color, dash, gap, width)


func _draw_dashed_segment(start: Vector2, finish: Vector2, color: Color, dash: float, gap: float, width: float) -> void:
	var vector: Vector2 = finish - start
	var length: float = vector.length()
	if length <= 0.001:
		return
	var direction: Vector2 = vector / length
	var cursor: float = 0.0
	while cursor < length:
		var segment_end: float = minf(cursor + dash, length)
		draw_line(start + direction * cursor, start + direction * segment_end, color, width, true)
		cursor += dash + gap


func _hit_connector_endpoint_handle(screen_position: Vector2, connector_id: int) -> int:
	if _runtime == null or not _runtime.model.connectors.contains(connector_id):
		return CONNECTOR_ENDPOINT_NONE
	var source_id: int = _runtime.model.connectors.get_source_entity_id(connector_id)
	var target_id: int = _runtime.model.connectors.get_target_entity_id(connector_id)
	if not _runtime.model.contains(source_id) or not _runtime.model.contains(target_id):
		return CONNECTOR_ENDPOINT_NONE
	var source_point: Vector2 = world_to_screen(ConnectorGeometry.anchor_position(
		_runtime.model.get_entity_bounds(source_id),
		_runtime.model.connectors.get_source_anchor(connector_id)
	))
	var target_point: Vector2 = world_to_screen(ConnectorGeometry.anchor_position(
		_runtime.model.get_entity_bounds(target_id),
		_runtime.model.connectors.get_target_anchor(connector_id)
	))
	if screen_position.distance_to(source_point) <= CONNECTOR_EDIT_HIT_RADIUS:
		return CONNECTOR_ENDPOINT_SOURCE
	if screen_position.distance_to(target_point) <= CONNECTOR_EDIT_HIT_RADIUS:
		return CONNECTOR_ENDPOINT_TARGET
	return CONNECTOR_ENDPOINT_NONE


func _hit_connector_router_handle(screen_position: Vector2, connector_id: int) -> int:
	if _runtime == null or not _runtime.model.connectors.contains(connector_id):
		return -1
	var points: PackedVector2Array = _runtime.model.connectors.get_router_points(connector_id)
	for index: int in range(points.size()):
		if screen_position.distance_to(world_to_screen(points[index])) <= CONNECTOR_EDIT_HIT_RADIUS:
			return index
	return -1


func _hit_resize_handle(screen_position: Vector2) -> int:
	if _runtime == null or _runtime.selection.size() != 1 or _editing_entity_id > 0:
		return HANDLE_NONE
	var entity_id: int = _runtime.selection.primary_id
	if (
		entity_id <= 0
		or not _runtime.model.contains(entity_id)
		or _runtime.model.get_entity_type(entity_id) == BoardEntityTypes.CONNECTOR
	):
		return HANDLE_NONE
	var bounds: Rect2 = _runtime.model.get_entity_bounds(entity_id)
	var screen_rect: Rect2 = Rect2(world_to_screen(bounds.position), bounds.size * zoom)
	var entity_type: StringName = _runtime.model.get_entity_type(entity_id)
	var corners: PackedVector2Array = _corner_handle_points(screen_rect)
	var corner_handles: PackedInt32Array = PackedInt32Array([
		HANDLE_TOP_LEFT,
		HANDLE_TOP_RIGHT,
		HANDLE_BOTTOM_RIGHT,
		HANDLE_BOTTOM_LEFT,
	])
	for index: int in range(corners.size()):
		if Rect2(corners[index] - Vector2.ONE * HANDLE_HIT_SIZE * 0.5, Vector2.ONE * HANDLE_HIT_SIZE).has_point(screen_position):
			return int(corner_handles[index])
	if entity_type != BoardEntityTypes.TEXT:
		return HANDLE_NONE
	var vertical_margin: float = minf(18.0, screen_rect.size.y * 0.25)
	var edge_top: float = screen_rect.position.y + vertical_margin
	var edge_bottom: float = screen_rect.end.y - vertical_margin
	if screen_position.y >= edge_top and screen_position.y <= edge_bottom:
		if absf(screen_position.x - screen_rect.position.x) <= HANDLE_HIT_SIZE * 0.5:
			return HANDLE_LEFT
		if absf(screen_position.x - screen_rect.end.x) <= HANDLE_HIT_SIZE * 0.5:
			return HANDLE_RIGHT
	return HANDLE_NONE


func _hit_connection_handle(screen_position: Vector2) -> int:
	if _runtime == null or _runtime.selection.size() != 1 or _editing_entity_id > 0:
		return -1
	var entity_id: int = _runtime.selection.primary_id
	if (
		entity_id <= 0
		or not _runtime.model.contains(entity_id)
		or _runtime.model.get_entity_type(entity_id) == BoardEntityTypes.CONNECTOR
	):
		return -1
	var bounds: Rect2 = _runtime.model.get_entity_bounds(entity_id)
	var screen_rect: Rect2 = Rect2(world_to_screen(bounds.position), bounds.size * zoom)
	var points: PackedVector2Array = _connection_handle_screen_points(screen_rect)
	for anchor: int in range(points.size()):
		if Rect2(points[anchor] - Vector2.ONE * 10.0, Vector2.ONE * 20.0).has_point(screen_position):
			return anchor
	return -1


func _corner_handle_points(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])


func _connection_handle_screen_points(rect: Rect2) -> PackedVector2Array:
	const OFFSET: float = 22.0
	return PackedVector2Array([
		Vector2(rect.get_center().x, rect.position.y - OFFSET),
		Vector2(rect.end.x + OFFSET, rect.get_center().y),
		Vector2(rect.get_center().x, rect.end.y + OFFSET),
		Vector2(rect.position.x - OFFSET, rect.get_center().y),
	])


func _normalized_world_pointer_rect() -> Rect2:
	return Rect2(_pointer_start_world, _pointer_current_world - _pointer_start_world).abs()


func _update_hover(screen_position: Vector2) -> void:
	_pointer_current_screen = screen_position
	_pointer_current_world = screen_to_world(screen_position)
	if _active_tool_id == BoardToolController.TOOL_DRAW and _drawing_eraser_enabled:
		queue_redraw()
	var next_hover: int = 0
	var next_cursor: Control.CursorShape = _default_cursor()
	if _runtime != null and _active_tool_id == BoardToolController.TOOL_SELECT and _pointer_action == ACTION_NONE and _editing_entity_id == 0:
		var selected_connector_id: int = _selected_connector_id()
		if selected_connector_id > 0 and _hit_connector_endpoint_handle(screen_position, selected_connector_id) != CONNECTOR_ENDPOINT_NONE:
			next_cursor = Control.CURSOR_POINTING_HAND
		elif selected_connector_id > 0 and _hit_connector_router_handle(screen_position, selected_connector_id) >= 0:
			next_cursor = Control.CURSOR_MOVE
		else:
			var connection_anchor: int = _hit_connection_handle(screen_position)
			if connection_anchor >= 0:
				next_cursor = Control.CURSOR_POINTING_HAND
			else:
				var handle: int = _hit_resize_handle(screen_position)
				if handle != HANDLE_NONE:
					next_cursor = _cursor_for_resize_handle(handle)
				else:
					var hit: BoardHitResult = _hit_test_selectable(screen_position)
					next_hover = hit.entity_id if hit.is_valid() else 0
					if next_hover > 0:
						next_cursor = (
							Control.CURSOR_POINTING_HAND
							if hit.type_id == BoardEntityTypes.CONNECTOR
							else Control.CURSOR_MOVE
						)
	if not _is_pointer_panning:
		mouse_default_cursor_shape = next_cursor
	if next_hover != _hover_entity_id:
		_hover_entity_id = next_hover
		queue_redraw()


func _hit_test_selectable(screen_position: Vector2) -> BoardHitResult:
	var empty: BoardHitResult = BoardHitResult.new()
	if _runtime == null:
		return empty
	var world_position: Vector2 = screen_to_world(screen_position)
	var selected_ids: PackedInt64Array = _runtime.selection.get_selected_ids()
	var selected_tolerance: float = 12.0 / maxf(zoom, 0.001)
	for index: int in range(selected_ids.size() - 1, -1, -1):
		var selected_id: int = int(selected_ids[index])
		if not _runtime.model.contains(selected_id):
			continue
		if _runtime.model.get_entity_type(selected_id) == BoardEntityTypes.CONNECTOR:
			continue
		var selected_bounds: Rect2 = _runtime.model.get_entity_bounds(selected_id).grow(selected_tolerance)
		if selected_bounds.has_point(world_position):
			var result: BoardHitResult = BoardHitResult.new()
			result.entity_id = selected_id
			result.type_id = _runtime.model.get_entity_type(selected_id)
			result.world_position = world_position
			result.local_position = world_position - _runtime.model.get_entity_bounds(selected_id).position
			result.z_order = _runtime.model.get_entity_z_order(selected_id)
			return result
	return _runtime.hit_test.hit_test_point(world_position, 12.0 / maxf(zoom, 0.001))


func _cursor_for_resize_handle(handle: int) -> Control.CursorShape:
	match handle:
		HANDLE_TOP_LEFT, HANDLE_BOTTOM_RIGHT:
			return Control.CURSOR_FDIAGSIZE
		HANDLE_TOP_RIGHT, HANDLE_BOTTOM_LEFT:
			return Control.CURSOR_BDIAGSIZE
		HANDLE_LEFT, HANDLE_RIGHT:
			return Control.CURSOR_HSIZE
		_:
			return Control.CURSOR_ARROW


func _build_render_layers() -> void:
	_grid_renderer = BoardGridRenderer.new()
	_grid_renderer.name = "BoardGridRenderer"
	add_child(_grid_renderer)
	_world_root = Node2D.new()
	_world_root.name = "BoardWorld"
	_world_root.show_behind_parent = true
	add_child(_world_root)
	_connector_renderer = ConnectorBatchRenderer.new()
	_connector_renderer.name = "ConnectorBatchRenderer"
	_world_root.add_child(_connector_renderer)
	_image_renderer = ImageBatchRenderer.new()
	_image_renderer.name = "ImageBatchRenderer"
	_world_root.add_child(_image_renderer)
	_pdf_renderer = PdfBatchRenderer.new()
	_pdf_renderer.name = "PdfBatchRenderer"
	_world_root.add_child(_pdf_renderer)
	_formula_renderer = FormulaBatchRenderer.new()
	_formula_renderer.name = "FormulaBatchRenderer"
	_world_root.add_child(_formula_renderer)
	_video_renderer = VideoBatchRenderer.new()
	_video_renderer.name = "VideoBatchRenderer"
	_world_root.add_child(_video_renderer)
	_audio_renderer = AudioBatchRenderer.new()
	_audio_renderer.name = "AudioBatchRenderer"
	_world_root.add_child(_audio_renderer)
	_note_portal_renderer = NotePortalBatchRenderer.new()
	_note_portal_renderer.name = "NotePortalBatchRenderer"
	_world_root.add_child(_note_portal_renderer)
	_stroke_renderer = StrokeBatchRenderer.new()
	_stroke_renderer.name = "StrokeBatchRenderer"
	_stroke_renderer.handoff_entities_ready.connect(_on_stroke_renderer_handoff_ready)
	_world_root.add_child(_stroke_renderer)
	_stroke_handoff_renderer = StrokeHandoffRenderer.new()
	_stroke_handoff_renderer.name = "StrokeHandoffRenderer"
	_world_root.add_child(_stroke_handoff_renderer)
	_text_renderer = TextBlockBatchRenderer.new()
	_text_renderer.name = "TextBlockBatchRenderer"
	_world_root.add_child(_text_renderer)


func _build_text_editor() -> void:
	_text_editor = TextEdit.new()
	_text_editor.name = "MaterializedTextEditor"
	_text_editor.visible = false
	_text_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text_editor.placeholder_text = ""
	_text_editor.z_index = 200
	_text_editor.context_menu_enabled = true
	_text_editor.selecting_enabled = true
	_text_editor.caret_multiple = false
	# Native TextEdit still owns input, IME and selection. Its caret is hidden and
	# redrawn by the board from the same rich layout as the visible glyphs.
	_text_editor.caret_blink = false
	_text_editor.deselect_on_focus_loss_enabled = false
	_text_editor.gui_input.connect(_on_text_editor_gui_input)
	_text_editor.text_changed.connect(_on_text_editor_text_changed)
	_text_editor.caret_changed.connect(_on_text_editor_caret_changed)
	_text_editor.focus_exited.connect(_on_text_editor_focus_exited)
	add_child(_text_editor)

	_editor_caret_timer = Timer.new()
	_editor_caret_timer.name = "RichTextCaretBlinkTimer"
	_editor_caret_timer.wait_time = 0.52
	_editor_caret_timer.one_shot = false
	_editor_caret_timer.timeout.connect(_on_editor_caret_blink_timeout)
	add_child(_editor_caret_timer)


func _sync_camera_visuals() -> void:
	if _grid_renderer != null:
		_grid_renderer.set_view(camera_position, zoom, size)
	if _world_root != null:
		_world_root.position = size * 0.5 - camera_position * zoom
		_world_root.scale = Vector2.ONE * zoom
	if _editing_entity_id > 0:
		_update_text_editor_layout()
	_emit_context_anchor()
	view_transform_changed.emit()


func _sync_text_renderer_hidden_ids() -> void:
	if _text_renderer == null:
		return
	var hidden_ids: Dictionary = _hidden_render_ids.duplicate()
	if _editing_entity_id > 0:
		hidden_ids[_editing_entity_id] = true
	for raw_id: Variant in _text_commit_handoff_ids.keys():
		hidden_ids[int(raw_id)] = true
	_text_renderer.set_hidden_entity_ids(hidden_ids)


func _sync_stroke_renderer_handoff_watch() -> void:
	if _stroke_renderer != null:
		_stroke_renderer.set_handoff_watch_ids(_stroke_commit_handoff_ids)
	if _stroke_handoff_renderer != null:
		_stroke_handoff_renderer.set_state(_stroke_commit_handoff_ids, _hidden_render_ids)


func _request_text_refresh(force: bool) -> void:
	_queue_render_refresh(RENDER_REFRESH_TEXT, force)


func _request_image_refresh(force: bool) -> void:
	_queue_render_refresh(RENDER_REFRESH_IMAGE, force)


func _request_pdf_refresh(force: bool) -> void:
	_queue_render_refresh(RENDER_REFRESH_PDF, force)


func _request_formula_refresh(force: bool) -> void:
	_queue_render_refresh(RENDER_REFRESH_FORMULA, force)


func _request_video_refresh(force: bool) -> void:
	_queue_render_refresh(RENDER_REFRESH_VIDEO, force)


func _request_audio_refresh(force: bool) -> void:
	_queue_render_refresh(RENDER_REFRESH_AUDIO, force)


func _request_note_portal_refresh(force: bool) -> void:
	_queue_render_refresh(RENDER_REFRESH_NOTE_PORTAL, force)


func _request_stroke_refresh(force: bool) -> void:
	_queue_render_refresh(RENDER_REFRESH_STROKE, force)


func _request_connector_refresh(force: bool) -> void:
	_queue_render_refresh(RENDER_REFRESH_CONNECTOR, force)


func _refresh_connectors_immediately() -> void:
	if _runtime == null or _connector_renderer == null:
		return
	# Connector handoffs are user-visible continuity points (create, drag release,
	# edit release). Bypass the frame-budgeted scheduler only for those points. The
	# regular queued path remains in use for background/viewport refreshes.
	_perform_connector_refresh(true)


func _refresh_note_portals_immediately() -> void:
	if _runtime == null or _note_portal_renderer == null:
		return
	# A transformed portal is hidden from the retained layer while the transient
	# interaction copy owns its pixels. Refresh synchronously at release so the old
	# retained bounds never flash for one presentation frame during handoff.
	_perform_note_portal_refresh(true)


func _queue_all_render_refreshes(force: bool) -> void:
	_queue_render_refresh(RENDER_REFRESH_ALL, force)


func _queue_render_refresh(refresh_mask: int, force: bool) -> void:
	if _runtime == null or refresh_mask == 0:
		return
	_render_pending_mask |= refresh_mask
	if force:
		_render_force_mask |= refresh_mask
	set_process(true)


func _flush_render_refresh_queue(interaction_active: bool) -> void:
	if _runtime == null or _render_pending_mask == 0:
		return
	# Retained board renderers already inherit the world transform. While camera
	# input is still arriving, rebuilding view-dependent geometry only creates
	# avoidable hitches. Forced model changes stay responsive; normal coverage/LOD
	# work starts after a quiet input window, even if the eased camera transform is
	# still finishing its last few pixels.
	var eligible_mask: int = _render_pending_mask
	if interaction_active:
		eligible_mask &= _render_force_mask
		if eligible_mask == 0:
			if _telemetry != null:
				_telemetry.record_developer_counter(&"render_motion_deferrals")
			return
	var rebuild_limit: int = mini(
		clampi(_runtime.render_policy.max_rebuilds_per_frame, 1, 5),
		MAX_RENDER_REBUILDS_PER_FRAME
	)
	if interaction_active:
		rebuild_limit = mini(rebuild_limit, MAX_RENDER_REBUILDS_WHILE_MOVING)
	var budget_usec: int = MOVING_RENDER_BUDGET_USEC if interaction_active else IDLE_RENDER_BUDGET_USEC
	var frame_start_usec: int = Time.get_ticks_usec()
	var rebuilds: int = 0
	var inspected: int = 0
	while eligible_mask != 0 and inspected < 9 and rebuilds < rebuild_limit:
		if Time.get_ticks_usec() - frame_start_usec >= budget_usec:
			if _telemetry != null:
				_telemetry.record_developer_counter(&"render_budget_hits")
			break
		var refresh_kind: int = _render_refresh_kind_at(_render_scheduler_cursor)
		_render_scheduler_cursor = (_render_scheduler_cursor + 1) % 9
		inspected += 1
		if (eligible_mask & refresh_kind) == 0:
			continue
		var force: bool = (_render_force_mask & refresh_kind) != 0
		_render_pending_mask &= ~refresh_kind
		_render_force_mask &= ~refresh_kind
		_render_model_pending_mask &= ~refresh_kind
		eligible_mask &= ~refresh_kind
		var rebuild_start_usec: int = Time.get_ticks_usec()
		if _perform_render_refresh(refresh_kind, force):
			rebuilds += 1
			_record_render_rebuild(refresh_kind, Time.get_ticks_usec() - rebuild_start_usec)


func _schedule_deferred_view_refresh_if_ready() -> void:
	if not _view_render_dirty or _runtime == null:
		return
	if _is_pointer_panning or _pointer_action != ACTION_NONE:
		return
	if _interaction_idle_seconds < VIEW_RENDER_DEBOUNCE_SECONDS:
		return
	_view_render_dirty = false
	_queue_all_render_refreshes(false)
	if _telemetry != null:
		_telemetry.record_developer_counter(&"view_refresh_commits")


func _target_visible_world_rect() -> Rect2:
	var safe_zoom: float = maxf(_target_zoom, 0.001)
	var world_size: Vector2 = size / safe_zoom
	return Rect2(_target_camera_position - world_size * 0.5, world_size)


func _render_refresh_kind_at(index: int) -> int:
	# Cheap/materialized categories are committed first. Stroke geometry is kept
	# last because a dense drawing rebuild can consume a complete frame by itself.
	match index:
		0:
			return RENDER_REFRESH_TEXT
		1:
			return RENDER_REFRESH_IMAGE
		2:
			return RENDER_REFRESH_PDF
		3:
			return RENDER_REFRESH_FORMULA
		4:
			return RENDER_REFRESH_VIDEO
		5:
			return RENDER_REFRESH_AUDIO
		6:
			return RENDER_REFRESH_NOTE_PORTAL
		7:
			return RENDER_REFRESH_CONNECTOR
		_:
			return RENDER_REFRESH_STROKE


func _perform_render_refresh(refresh_kind: int, force: bool) -> bool:
	match refresh_kind:
		RENDER_REFRESH_TEXT:
			return _perform_text_refresh(force)
		RENDER_REFRESH_STROKE:
			return _perform_stroke_refresh(force)
		RENDER_REFRESH_CONNECTOR:
			return _perform_connector_refresh(force)
		RENDER_REFRESH_IMAGE:
			return _perform_image_refresh(force)
		RENDER_REFRESH_PDF:
			return _perform_pdf_refresh(force)
		RENDER_REFRESH_FORMULA:
			return _perform_formula_refresh(force)
		RENDER_REFRESH_VIDEO:
			return _perform_video_refresh(force)
		RENDER_REFRESH_AUDIO:
			return _perform_audio_refresh(force)
		RENDER_REFRESH_NOTE_PORTAL:
			return _perform_note_portal_refresh(force)
		_:
			return false


func _perform_text_refresh(force: bool) -> bool:
	if _runtime == null or _text_renderer == null:
		return false
	var render_zoom: float = _target_zoom
	var visible_rect: Rect2 = _target_visible_world_rect()
	var lod: BoardRenderPolicy.LodLevel = _current_lod_level(render_zoom)
	var revision: int = _runtime.model.text_revision
	var editing_changed: bool = _render_editing_id != _editing_entity_id
	var extra_margin: float = maxf(
		320.0 / maxf(render_zoom, 0.001),
		maxf(visible_rect.size.x, visible_rect.size.y) * 0.28
	)
	var coverage: Rect2 = visible_rect.grow(extra_margin)
	if (
		not force
		and not editing_changed
		and _render_lod == int(lod)
		and _render_model_revision == revision
		and _coverage_is_reusable(_render_coverage_rect, visible_rect, coverage)
	):
		return false
	var candidates: PackedInt64Array = _render_candidates_for_type(coverage, BoardEntityTypes.TEXT)
	var visible_ids: PackedInt64Array = _collect_visible_text_ids(candidates)
	var snapshot: Dictionary = _runtime.model.text_blocks.create_render_snapshot(
		visible_ids,
		_runtime.model.transforms,
		lod,
		_editing_entity_id
	)
	snapshot["max_text_previews"] = _runtime.render_policy.max_visible_text_previews
	snapshot["max_text_lines"] = _runtime.render_policy.max_text_lines_per_block
	var signature: String = "%d:%d:%d:%d:%d:%d:%d:%d:%d:%d" % [
		int(_runtime.get_instance_id()),
		revision,
		int(lod),
		_editing_entity_id,
		int(round(coverage.position.x)),
		int(round(coverage.position.y)),
		int(round(coverage.size.x)),
		int(round(coverage.size.y)),
		visible_ids.size(),
		hash(visible_ids),
	]
	_expected_text_signature = signature
	if not _text_worker.submit(snapshot, signature):
		# A worker may still be publishing the previous plan. Do not advance the
		# retained revision until the new snapshot is actually accepted; otherwise
		# text can remain absent until an unrelated model change happens. Requeue the
		# request for a later frame instead.
		_queue_render_refresh(RENDER_REFRESH_TEXT, force)
		_queue_changed_model_refreshes()
		return false
	_text_plan_pending = true
	if _telemetry != null:
		_telemetry.record_developer_counter(&"text_submits")
	_render_coverage_rect = coverage
	_render_lod = int(lod)
	_render_model_revision = revision
	_render_editing_id = _editing_entity_id
	return true


func _perform_image_refresh(force: bool) -> bool:
	if _runtime == null or _image_renderer == null:
		return false
	var render_zoom: float = _target_zoom
	var visible_rect: Rect2 = _target_visible_world_rect()
	var revision: int = _runtime.model.image_revision
	var zoom_bucket: int = _zoom_bucket_with_hysteresis(render_zoom, _image_render_zoom_bucket)
	var extra_margin: float = maxf(
		360.0 / maxf(render_zoom, 0.001),
		maxf(visible_rect.size.x, visible_rect.size.y) * 0.30
	)
	var coverage: Rect2 = visible_rect.grow(extra_margin)
	if (
		not force
		and _image_model_revision == revision
		and _image_render_zoom_bucket == zoom_bucket
		and _coverage_is_reusable(_image_coverage_rect, visible_rect, coverage)
	):
		return false
	var candidates: PackedInt64Array = _render_candidates_for_type(coverage, BoardEntityTypes.IMAGE)
	_image_renderer.rebuild(
		_runtime,
		_image_cache,
		candidates,
		_runtime.render_policy.max_visible_images,
		render_zoom
	)
	_image_renderer.set_hidden_entity_ids(_hidden_render_ids)
	_image_coverage_rect = coverage
	_image_model_revision = revision
	_image_render_zoom_bucket = zoom_bucket
	return true


func _perform_pdf_refresh(force: bool) -> bool:
	if _runtime == null or _pdf_renderer == null:
		return false
	var render_zoom: float = _target_zoom
	var visible_rect: Rect2 = _target_visible_world_rect()
	var revision: int = _runtime.model.pdf_revision
	var zoom_bucket: int = _zoom_bucket_with_hysteresis(render_zoom, _pdf_render_zoom_bucket)
	var extra_margin: float = maxf(360.0 / maxf(render_zoom, 0.001), maxf(visible_rect.size.x, visible_rect.size.y) * 0.30)
	var coverage: Rect2 = visible_rect.grow(extra_margin)
	if (
		not force
		and _pdf_model_revision == revision
		and _pdf_render_zoom_bucket == zoom_bucket
		and _coverage_is_reusable(_pdf_coverage_rect, visible_rect, coverage)
	):
		return false
	var candidates: PackedInt64Array = _render_candidates_for_type(coverage, BoardEntityTypes.PDF)
	_pdf_renderer.rebuild(_runtime, _pdf_media, candidates, _runtime.render_policy.max_visible_pdf_pages, render_zoom, _target_camera_position)
	_pdf_renderer.set_hidden_entity_ids(_hidden_render_ids)
	_pdf_coverage_rect = coverage
	_pdf_model_revision = revision
	_pdf_render_zoom_bucket = zoom_bucket
	return true


func _perform_formula_refresh(force: bool) -> bool:
	if _runtime == null or _formula_renderer == null:
		return false
	var render_zoom: float = _target_zoom
	var visible_rect: Rect2 = _target_visible_world_rect()
	var revision: int = _runtime.model.formula_revision
	var zoom_bucket: int = _zoom_bucket_with_hysteresis(render_zoom, _formula_render_zoom_bucket)
	var extra_margin: float = maxf(300.0 / maxf(render_zoom, 0.001), maxf(visible_rect.size.x, visible_rect.size.y) * 0.25)
	var coverage: Rect2 = visible_rect.grow(extra_margin)
	if not force and _formula_model_revision == revision and _formula_render_zoom_bucket == zoom_bucket and _coverage_is_reusable(_formula_coverage_rect, visible_rect, coverage):
		return false
	var candidates: PackedInt64Array = _render_candidates_for_type(coverage, BoardEntityTypes.FORMULA)
	_formula_renderer.rebuild(_runtime, _formula_render, candidates, _runtime.render_policy.max_visible_formulas, render_zoom, _target_camera_position)
	_formula_renderer.set_hidden_entity_ids(_hidden_render_ids)
	_formula_coverage_rect = coverage
	_formula_model_revision = revision
	_formula_render_zoom_bucket = zoom_bucket
	return true


func _perform_video_refresh(force: bool) -> bool:
	if _runtime == null or _video_renderer == null:
		return false
	var render_zoom: float = _target_zoom
	var visible_rect: Rect2 = _target_visible_world_rect()
	var revision: int = _runtime.model.video_revision
	var zoom_bucket: int = _zoom_bucket_with_hysteresis(render_zoom, _video_render_zoom_bucket)
	var extra_margin: float = maxf(
		360.0 / maxf(render_zoom, 0.001),
		maxf(visible_rect.size.x, visible_rect.size.y) * 0.30
	)
	var coverage: Rect2 = visible_rect.grow(extra_margin)
	if (
		not force
		and _video_model_revision == revision
		and _video_render_zoom_bucket == zoom_bucket
		and _coverage_is_reusable(_video_coverage_rect, visible_rect, coverage)
	):
		return false
	var candidates: PackedInt64Array = _render_candidates_for_type(coverage, BoardEntityTypes.VIDEO)
	_video_renderer.rebuild(
		_runtime,
		_video_media,
		candidates,
		_runtime.render_policy.max_visible_videos,
		render_zoom,
		_target_camera_position
	)
	_video_renderer.set_hidden_entity_ids(_hidden_render_ids)
	_video_coverage_rect = coverage
	_video_model_revision = revision
	_video_render_zoom_bucket = zoom_bucket
	return true


func _perform_audio_refresh(force: bool) -> bool:
	if _runtime == null or _audio_renderer == null:
		return false
	var render_zoom: float = _target_zoom
	var visible_rect: Rect2 = _target_visible_world_rect()
	var revision: int = _runtime.model.audio_revision
	var zoom_bucket: int = _zoom_bucket_with_hysteresis(render_zoom, _audio_render_zoom_bucket)
	var extra_margin: float = maxf(300.0 / maxf(render_zoom, 0.001), maxf(visible_rect.size.x, visible_rect.size.y) * 0.25)
	var coverage: Rect2 = visible_rect.grow(extra_margin)
	if (
		not force
		and _audio_model_revision == revision
		and _audio_render_zoom_bucket == zoom_bucket
		and _coverage_is_reusable(_audio_coverage_rect, visible_rect, coverage)
	):
		return false
	var candidates: PackedInt64Array = _render_candidates_for_type(coverage, BoardEntityTypes.AUDIO)
	_audio_renderer.rebuild(_runtime, _audio_media, candidates, _runtime.render_policy.max_visible_audios, render_zoom, _target_camera_position)
	_audio_renderer.set_hidden_entity_ids(_hidden_render_ids)
	_audio_coverage_rect = coverage
	_audio_model_revision = revision
	_audio_render_zoom_bucket = zoom_bucket
	return true


func _perform_note_portal_refresh(force: bool) -> bool:
	if _runtime == null or _note_portal_renderer == null:
		return false
	var render_zoom: float = _target_zoom
	var visible_rect: Rect2 = _target_visible_world_rect()
	var revision: int = _runtime.model.note_portal_revision
	var zoom_bucket: int = _zoom_bucket_with_hysteresis(render_zoom, _note_portal_render_zoom_bucket)
	var extra_margin: float = maxf(
		300.0 / maxf(render_zoom, 0.001),
		maxf(visible_rect.size.x, visible_rect.size.y) * 0.25
	)
	var coverage: Rect2 = visible_rect.grow(extra_margin)
	if (
		not force
		and _note_portal_model_revision == revision
		and _note_portal_render_zoom_bucket == zoom_bucket
		and _coverage_is_reusable(_note_portal_coverage_rect, visible_rect, coverage)
	):
		return false
	var candidates: PackedInt64Array = _render_candidates_for_type(coverage, BoardEntityTypes.NOTE_PORTAL)
	_note_portal_renderer.rebuild(
		_runtime,
		_note_repository,
		_formula_render,
		candidates,
		_runtime.render_policy.max_visible_note_portals,
		render_zoom,
		_full_note_card_render,
		_target_camera_position
	)
	_note_portal_renderer.set_hidden_entity_ids(_hidden_render_ids)
	_note_portal_renderer.set_live_entity_ids(_live_note_surface_ids)
	_note_portal_coverage_rect = coverage
	_note_portal_model_revision = revision
	_note_portal_render_zoom_bucket = zoom_bucket
	return true


func _perform_stroke_refresh(force: bool) -> bool:
	if _runtime == null or _stroke_renderer == null:
		return false
	var render_zoom: float = _target_zoom
	var visible_rect: Rect2 = _target_visible_world_rect()
	var revision: int = _runtime.model.stroke_revision
	var lod: BoardRenderPolicy.LodLevel = _current_stroke_lod_level(render_zoom)
	var zoom_bucket: int = _zoom_bucket_with_hysteresis(render_zoom, _stroke_render_zoom_bucket)
	var extra_margin: float = maxf(
		240.0 / maxf(render_zoom, 0.001),
		maxf(visible_rect.size.x, visible_rect.size.y) * 0.22
	)
	var coverage: Rect2 = visible_rect.grow(extra_margin)
	if (
		not force
		and _stroke_model_revision == revision
		and _stroke_render_lod == int(lod)
		and _coverage_is_reusable(_stroke_coverage_rect, visible_rect, coverage)
	):
		return false
	var candidates: PackedInt64Array = _render_candidates_for_type(coverage, BoardEntityTypes.STROKE)
	_stroke_renderer.rebuild(candidates, render_zoom, int(lod), zoom_bucket)
	_stroke_renderer.set_hidden_entity_ids(_hidden_render_ids)
	_stroke_coverage_rect = coverage
	_stroke_model_revision = revision
	_stroke_render_zoom_bucket = zoom_bucket
	_stroke_render_lod = int(lod)
	return true


func _perform_connector_refresh(force: bool) -> bool:
	if _runtime == null or _connector_renderer == null:
		return false
	var render_zoom: float = _target_zoom
	var visible_rect: Rect2 = _target_visible_world_rect()
	var revision: int = _runtime.model.connector_revision
	var zoom_bucket: int = _zoom_bucket_with_hysteresis(render_zoom, _connector_render_zoom_bucket)
	var lod: BoardRenderPolicy.LodLevel = _current_lod_level(render_zoom)
	var extra_margin: float = maxf(
		360.0 / maxf(render_zoom, 0.001),
		maxf(visible_rect.size.x, visible_rect.size.y) * 0.30
	)
	var coverage: Rect2 = visible_rect.grow(extra_margin)
	if (
		not force
		and _connector_model_revision == revision
		and _connector_render_zoom_bucket == zoom_bucket
		and _connector_render_lod == int(lod)
		and _coverage_is_reusable(_connector_coverage_rect, visible_rect, coverage)
	):
		return false
	var candidates: PackedInt64Array = _render_candidates_for_type(coverage, BoardEntityTypes.CONNECTOR)
	_connector_renderer.set_hidden_connector_ids(_hidden_connector_ids, false)
	_connector_renderer.rebuild(
		_runtime,
		candidates,
		_runtime.render_policy.max_visible_connectors,
		render_zoom,
		_runtime.render_policy.max_visible_connector_segments,
		int(lod),
		_target_camera_position
	)
	_connector_coverage_rect = coverage
	_connector_model_revision = revision
	_connector_render_zoom_bucket = zoom_bucket
	_connector_render_lod = int(lod)
	return true


func _render_candidates_for_type(requested_coverage: Rect2, type_id: StringName) -> PackedInt64Array:
	_ensure_shared_visibility(requested_coverage)
	var measure_filter: bool = _telemetry != null and _telemetry.developer_diagnostics_enabled()
	var filter_start_usec: int = Time.get_ticks_usec() if measure_filter else -1
	var source: PackedInt64Array = PackedInt64Array()
	match type_id:
		BoardEntityTypes.TEXT:
			source = _shared_text_candidates
		BoardEntityTypes.IMAGE:
			source = _shared_image_candidates
		BoardEntityTypes.PDF:
			source = _shared_pdf_candidates
		BoardEntityTypes.FORMULA:
			source = _shared_formula_candidates
		BoardEntityTypes.VIDEO:
			source = _shared_video_candidates
		BoardEntityTypes.AUDIO:
			source = _shared_audio_candidates
		BoardEntityTypes.NOTE_PORTAL:
			source = _shared_note_portal_candidates
		BoardEntityTypes.STROKE:
			source = _shared_stroke_candidates
		BoardEntityTypes.CONNECTOR:
			source = _shared_connector_candidates
		_:
			return PackedInt64Array()
	# The shared spatial query deliberately covers the largest renderer overscan.
	# Returning that whole set to every renderer made strokes inherit the media
	# margin and retain substantially more geometry than their own coverage needs.
	# A cheap bounds filter preserves the single spatial query while restoring each
	# renderer's intended working set.
	var filtered: PackedInt64Array = PackedInt64Array()
	for entity_id: int in source:
		if _runtime.model.get_entity_bounds(entity_id).intersects(requested_coverage, true):
			filtered.append(entity_id)
	if measure_filter:
		_telemetry.record_developer_timing_usec(&"candidate_filter", Time.get_ticks_usec() - filter_start_usec)
		_telemetry.record_developer_counter(&"candidate_filters")
	return filtered


func _ensure_shared_visibility(requested_coverage: Rect2) -> void:
	if _runtime == null:
		_clear_shared_visibility()
		return
	var spatial_revision: int = _runtime.spatial_index.get_revision()
	if (
		_shared_visibility_revision == spatial_revision
		and _coverage_is_reusable(_shared_visibility_coverage, requested_coverage, requested_coverage)
	):
		return
	var visible_rect: Rect2 = _target_visible_world_rect()
	var shared_margin: float = maxf(
		360.0 / maxf(_target_zoom, 0.001),
		maxf(visible_rect.size.x, visible_rect.size.y) * 0.30
	)
	var query_coverage: Rect2 = visible_rect.grow(shared_margin).merge(requested_coverage)
	var query_start_usec: int = Time.get_ticks_usec()
	var candidates: PackedInt64Array = _runtime.spatial_index.query_rect(query_coverage)
	_shared_text_candidates = PackedInt64Array()
	_shared_image_candidates = PackedInt64Array()
	_shared_pdf_candidates = PackedInt64Array()
	_shared_formula_candidates = PackedInt64Array()
	_shared_video_candidates = PackedInt64Array()
	_shared_audio_candidates = PackedInt64Array()
	_shared_note_portal_candidates = PackedInt64Array()
	_shared_stroke_candidates = PackedInt64Array()
	_shared_connector_candidates = PackedInt64Array()
	for entity_id: int in candidates:
		match _runtime.model.get_entity_type(entity_id):
			BoardEntityTypes.TEXT:
				_shared_text_candidates.append(entity_id)
			BoardEntityTypes.IMAGE:
				_shared_image_candidates.append(entity_id)
			BoardEntityTypes.PDF:
				_shared_pdf_candidates.append(entity_id)
			BoardEntityTypes.FORMULA:
				_shared_formula_candidates.append(entity_id)
			BoardEntityTypes.VIDEO:
				_shared_video_candidates.append(entity_id)
			BoardEntityTypes.AUDIO:
				_shared_audio_candidates.append(entity_id)
			BoardEntityTypes.NOTE_PORTAL:
				_shared_note_portal_candidates.append(entity_id)
			BoardEntityTypes.STROKE:
				_shared_stroke_candidates.append(entity_id)
			BoardEntityTypes.CONNECTOR:
				_shared_connector_candidates.append(entity_id)
	_shared_visibility_coverage = query_coverage
	_shared_visibility_revision = spatial_revision
	if _telemetry != null:
		_telemetry.record_developer_counter(&"spatial_queries")
		_telemetry.record_developer_timing_usec(&"spatial_query", Time.get_ticks_usec() - query_start_usec)
		_telemetry.set_developer_gauge(&"visible_candidates", float(candidates.size()))


func _coverage_is_reusable(existing: Rect2, required_visible: Rect2, desired_coverage: Rect2) -> bool:
	if not existing.has_area() or not required_visible.has_area() or not desired_coverage.has_area():
		return false
	if not existing.encloses(required_visible):
		return false
	# Overscan is retained to avoid rebuilds during small camera moves, but a very
	# large stale coverage after zooming in keeps thousands of off-screen draw
	# commands alive. Rebuild once the retained area is substantially larger than
	# what the current target view needs.
	var desired_area: float = maxf(desired_coverage.get_area(), 1.0)
	return existing.get_area() <= desired_area * COVERAGE_RETENTION_AREA_RATIO


func _clear_shared_visibility() -> void:
	_shared_visibility_coverage = Rect2()
	_shared_visibility_revision = -1
	_shared_text_candidates = PackedInt64Array()
	_shared_image_candidates = PackedInt64Array()
	_shared_pdf_candidates = PackedInt64Array()
	_shared_formula_candidates = PackedInt64Array()
	_shared_video_candidates = PackedInt64Array()
	_shared_audio_candidates = PackedInt64Array()
	_shared_note_portal_candidates = PackedInt64Array()
	_shared_stroke_candidates = PackedInt64Array()
	_shared_connector_candidates = PackedInt64Array()
	if _telemetry != null:
		_telemetry.set_developer_gauge(&"visible_candidates", 0.0)


func _collect_visible_text_ids(candidates: PackedInt64Array) -> PackedInt64Array:
	var result: PackedInt64Array = PackedInt64Array()
	if _runtime == null:
		return result
	var values: Array[int] = []
	for entity_id: int in candidates:
		if _hidden_render_ids.has(entity_id) and not _include_hidden_in_text_plan:
			continue
		if _runtime.model.get_entity_type(entity_id) == BoardEntityTypes.TEXT and _runtime.model.text_blocks.contains(entity_id):
			values.append(entity_id)
	var budget: int = maxi(1, _runtime.render_policy.max_visible_text_blocks)
	if values.size() > budget:
		values.sort_custom(_sort_by_distance_to_camera)
		values.resize(budget)
	values.sort_custom(_sort_by_z_order)
	result.resize(values.size())
	for index: int in range(values.size()):
		result[index] = values[index]
	return result


func _current_lod_level(zoom_value: float = -1.0) -> BoardRenderPolicy.LodLevel:
	if _runtime == null:
		return BoardRenderPolicy.LodLevel.FULL
	var reference_zoom: float = zoom_value if zoom_value > 0.0 else _target_zoom
	var lod: BoardRenderPolicy.LodLevel = _runtime.render_policy.lod_for_zoom_hysteretic(reference_zoom, _stable_lod_level)
	_stable_lod_level = int(lod)
	return lod


func _current_stroke_lod_level(zoom_value: float = -1.0) -> BoardRenderPolicy.LodLevel:
	if _runtime == null:
		return BoardRenderPolicy.LodLevel.FULL
	var reference_zoom: float = zoom_value if zoom_value > 0.0 else _target_zoom
	# Strokes are by far the most expensive retained primitive on dense boards.
	# Keep their lightweight MEDIUM representation through the 70–90% range,
	# while still restoring the exact brush rendering around normal 100% zoom.
	if _stable_stroke_lod_level == int(BoardRenderPolicy.LodLevel.FULL) and reference_zoom >= STROKE_FULL_LEAVE_ZOOM:
		return BoardRenderPolicy.LodLevel.FULL
	var hysteresis_reference: int = _stable_stroke_lod_level
	if hysteresis_reference == int(BoardRenderPolicy.LodLevel.FULL):
		hysteresis_reference = int(BoardRenderPolicy.LodLevel.MEDIUM)
	var lod: BoardRenderPolicy.LodLevel = _runtime.render_policy.lod_for_zoom_hysteretic(reference_zoom, hysteresis_reference)
	if lod == BoardRenderPolicy.LodLevel.FULL and reference_zoom < STROKE_FULL_ENTER_ZOOM:
		lod = BoardRenderPolicy.LodLevel.MEDIUM
	_stable_stroke_lod_level = int(lod)
	return lod


func _zoom_bucket_with_hysteresis(value: float, previous_bucket: int) -> int:
	var normalized: float = log(maxf(value, MIN_ZOOM)) / log(ZOOM_BUCKET_BASE)
	var candidate: int = int(round(normalized))
	if previous_bucket == -999 or candidate == previous_bucket:
		return candidate
	var upper_boundary: float = float(previous_bucket) + 0.5 + ZOOM_BUCKET_HYSTERESIS
	var lower_boundary: float = float(previous_bucket) - 0.5 - ZOOM_BUCKET_HYSTERESIS
	if normalized > upper_boundary or normalized < lower_boundary:
		return candidate
	return previous_bucket


func get_developer_diagnostics_snapshot() -> Dictionary:
	# Diagnostics must never mutate render state. In particular, asking for a
	# snapshot must not advance LOD hysteresis and accidentally change what the
	# next real renderer refresh chooses.
	var lod_level: int = _stable_lod_level
	var stroke_lod_level: int = _stable_stroke_lod_level
	if _runtime == null:
		lod_level = int(BoardRenderPolicy.LodLevel.FULL)
		stroke_lod_level = int(BoardRenderPolicy.LodLevel.FULL)
	elif lod_level < int(BoardRenderPolicy.LodLevel.FULL) or lod_level > int(BoardRenderPolicy.LodLevel.PLACEHOLDER):
		lod_level = int(_runtime.render_policy.lod_for_zoom(_target_zoom))
	if _runtime != null and (stroke_lod_level < int(BoardRenderPolicy.LodLevel.FULL) or stroke_lod_level > int(BoardRenderPolicy.LodLevel.PLACEHOLDER)):
		stroke_lod_level = int(_runtime.render_policy.lod_for_zoom(_target_zoom))
		if stroke_lod_level == int(BoardRenderPolicy.LodLevel.FULL) and _target_zoom < STROKE_FULL_ENTER_ZOOM:
			stroke_lod_level = int(BoardRenderPolicy.LodLevel.MEDIUM)
	var visible_rect: Rect2 = _target_visible_world_rect()
	var visible_area: float = maxf(visible_rect.get_area(), 1.0)
	var camera_delta_screen: float = camera_position.distance_to(_target_camera_position) * maxf(zoom, 0.001)
	return {
		"zoom_percent": int(round(zoom * 100.0)),
		"target_zoom_percent": int(round(_target_zoom * 100.0)),
		"camera_moving": not camera_position.is_equal_approx(_target_camera_position) or not is_equal_approx(zoom, _target_zoom) or _is_pointer_panning,
		"camera_input_idle_ms": int(round(_interaction_idle_seconds * 1000.0)),
		"camera_target_delta_px": camera_delta_screen,
		"zoom_target_delta_percent": absf(zoom - _target_zoom) * 100.0,
		"view_refresh_deferred": _view_render_dirty,
		"render_pending_mask": _render_pending_mask,
		"render_force_mask": _render_force_mask,
		"lod": _lod_name(lod_level),
		"stroke_lod": _lod_name(stroke_lod_level),
		"visible_world_width": visible_rect.size.x,
		"visible_world_height": visible_rect.size.y,
		"shared_coverage_ratio": _shared_visibility_coverage.get_area() / visible_area if _shared_visibility_coverage.has_area() else 0.0,
		"stroke_coverage_ratio": _stroke_coverage_rect.get_area() / visible_area if _stroke_coverage_rect.has_area() else 0.0,
		"visible_candidates_total": _shared_text_candidates.size() + _shared_image_candidates.size() + _shared_pdf_candidates.size() + _shared_video_candidates.size() + _shared_audio_candidates.size() + _shared_stroke_candidates.size() + _shared_connector_candidates.size(),
		"visible_text_candidates": _shared_text_candidates.size(),
		"visible_image_candidates": _shared_image_candidates.size(),
		"visible_pdf_candidates": _shared_pdf_candidates.size(),
		"visible_video_candidates": _shared_video_candidates.size(),
		"visible_audio_candidates": _shared_audio_candidates.size(),
		"visible_stroke_candidates": _shared_stroke_candidates.size(),
		"visible_connector_candidates": _shared_connector_candidates.size(),
		"stroke_segments": _stroke_renderer.get_last_segment_count() if _stroke_renderer != null else 0,
		"stroke_requested_lod": _stroke_renderer.get_requested_lod_level() if _stroke_renderer != null else stroke_lod_level,
		"stroke_effective_lod": _stroke_renderer.get_effective_lod_level() if _stroke_renderer != null else stroke_lod_level,
		"stroke_adaptive_point_limit": _stroke_renderer.get_adaptive_point_limit() if _stroke_renderer != null else 0,
		"stroke_target_segments": _stroke_renderer.get_effective_segment_budget() if _stroke_renderer != null else 0,
		"connector_segments": _connector_renderer.get_last_segment_count() if _connector_renderer != null else 0,
		"context_ui_suppressed": _context_ui_suppressed,
		"context_anchor_dirty": _context_anchor_dirty,
		"context_anchor_visible": _last_context_anchor_visible,
		"context_signal_initialized": _context_signal_initialized,
		"context_anchor_width": _last_context_anchor_rect.size.x,
		"context_anchor_height": _last_context_anchor_rect.size.y,
	}


func _update_developer_view_gauges(view_moving: bool) -> void:
	if _telemetry == null or not _telemetry.developer_diagnostics_enabled():
		return
	_telemetry.set_developer_gauge(&"zoom_percent", zoom * 100.0)
	_telemetry.set_developer_gauge(&"target_zoom_percent", _target_zoom * 100.0)
	_telemetry.set_developer_gauge(&"camera_moving", 1.0 if view_moving else 0.0)
	_telemetry.set_developer_gauge(&"camera_input_idle_ms", _interaction_idle_seconds * 1000.0)
	_telemetry.set_developer_gauge(&"camera_target_delta_px", camera_position.distance_to(_target_camera_position) * maxf(zoom, 0.001))
	_telemetry.set_developer_gauge(&"view_refresh_deferred", 1.0 if _view_render_dirty else 0.0)
	_telemetry.set_developer_gauge(&"render_pending_mask", float(_render_pending_mask))
	_telemetry.set_developer_gauge(&"visible_text_candidates", float(_shared_text_candidates.size()))
	_telemetry.set_developer_gauge(&"visible_image_candidates", float(_shared_image_candidates.size()))
	_telemetry.set_developer_gauge(&"visible_pdf_candidates", float(_shared_pdf_candidates.size()))
	_telemetry.set_developer_gauge(&"visible_formula_candidates", float(_shared_formula_candidates.size()))
	_telemetry.set_developer_gauge(&"visible_video_candidates", float(_shared_video_candidates.size()))
	_telemetry.set_developer_gauge(&"visible_audio_candidates", float(_shared_audio_candidates.size()))
	_telemetry.set_developer_gauge(&"visible_stroke_candidates", float(_shared_stroke_candidates.size()))
	_telemetry.set_developer_gauge(&"visible_connector_candidates", float(_shared_connector_candidates.size()))
	_telemetry.set_developer_gauge(&"lod_level", float(_stable_lod_level))
	_telemetry.set_developer_gauge(&"stroke_lod_level", float(_stable_stroke_lod_level))


func _lod_name(lod_level: int) -> String:
	match lod_level:
		BoardRenderPolicy.LodLevel.MEDIUM:
			return NotLightL10n.text("developer.diagnostics.lod.medium")
		BoardRenderPolicy.LodLevel.LOW:
			return NotLightL10n.text("developer.diagnostics.lod.low")
		BoardRenderPolicy.LodLevel.PLACEHOLDER:
			return NotLightL10n.text("developer.diagnostics.lod.placeholder")
		_:
			return NotLightL10n.text("developer.diagnostics.lod.full")


func _record_render_rebuild(refresh_kind: int, elapsed_usec: int) -> void:
	if _telemetry == null:
		return
	_telemetry.record_developer_counter(&"rebuilds")
	_telemetry.record_developer_timing_usec(&"rebuild_time", elapsed_usec)
	match refresh_kind:
		RENDER_REFRESH_TEXT:
			_telemetry.record_developer_counter(&"rebuild_text")
			_telemetry.record_developer_timing_usec(&"rebuild_text", elapsed_usec)
		RENDER_REFRESH_STROKE:
			_telemetry.record_developer_counter(&"rebuild_stroke")
			_telemetry.record_developer_timing_usec(&"rebuild_stroke", elapsed_usec)
		RENDER_REFRESH_CONNECTOR:
			_telemetry.record_developer_counter(&"rebuild_connector")
			_telemetry.record_developer_timing_usec(&"rebuild_connector", elapsed_usec)
		RENDER_REFRESH_IMAGE:
			_telemetry.record_developer_counter(&"rebuild_image")
			_telemetry.record_developer_timing_usec(&"rebuild_image", elapsed_usec)
		RENDER_REFRESH_PDF:
			_telemetry.record_developer_counter(&"rebuild_pdf")
			_telemetry.record_developer_timing_usec(&"rebuild_pdf", elapsed_usec)
		RENDER_REFRESH_FORMULA:
			_telemetry.record_developer_counter(&"rebuild_formula")
			_telemetry.record_developer_timing_usec(&"rebuild_formula", elapsed_usec)
		RENDER_REFRESH_VIDEO:
			_telemetry.record_developer_counter(&"rebuild_video")
			_telemetry.record_developer_timing_usec(&"rebuild_video", elapsed_usec)
		RENDER_REFRESH_AUDIO:
			_telemetry.record_developer_counter(&"rebuild_audio")
			_telemetry.record_developer_timing_usec(&"rebuild_audio", elapsed_usec)
		RENDER_REFRESH_NOTE_PORTAL:
			_telemetry.record_developer_counter(&"rebuild_note_portal")
			_telemetry.record_developer_timing_usec(&"rebuild_note_portal", elapsed_usec)


func _sort_by_distance_to_camera(left_id: int, right_id: int) -> bool:
	if _runtime == null:
		return left_id < right_id
	var left_center: Vector2 = _runtime.model.get_entity_bounds(left_id).get_center()
	var right_center: Vector2 = _runtime.model.get_entity_bounds(right_id).get_center()
	var left_distance: float = left_center.distance_squared_to(_target_camera_position)
	var right_distance: float = right_center.distance_squared_to(_target_camera_position)
	if not is_equal_approx(left_distance, right_distance):
		return left_distance < right_distance
	return left_id < right_id


func _sort_by_z_order(left_id: int, right_id: int) -> bool:
	if _runtime == null:
		return left_id < right_id
	var left_z: int = _runtime.model.get_entity_z_order(left_id)
	var right_z: int = _runtime.model.get_entity_z_order(right_id)
	return left_z < right_z if left_z != right_z else left_id < right_id


func _poll_text_worker() -> void:
	var result: Dictionary = _text_worker.poll_result()
	if result.is_empty():
		return
	var result_signature: String = str(result.get("signature", ""))
	if result_signature == _expected_text_signature:
		var apply_start_usec: int = Time.get_ticks_usec()
		_text_renderer.apply_plan(result)
		if _telemetry != null:
			_telemetry.record_developer_counter(&"text_applies")
			_telemetry.record_developer_timing_usec(&"text_apply", Time.get_ticks_usec() - apply_start_usec)
		var hidden_state_changed: bool = false
		var plan_matches_current_text_state: bool = (
			_runtime != null
			and _render_editing_id == _editing_entity_id
			and _render_model_revision == _runtime.model.text_revision
		)
		# A worker result submitted while the editor was still open can finish after
		# commit. Keep the transient handoff until a plan for the current text
		# revision and current editing state has actually been applied.
		if plan_matches_current_text_state and not _text_commit_handoff_ids.is_empty():
			_text_commit_handoff_ids.clear()
			hidden_state_changed = true
		if _unhide_text_after_plan:
			_unhide_text_after_plan = false
			_hidden_render_ids.clear()
			hidden_state_changed = true
		if hidden_state_changed:
			_sync_text_renderer_hidden_ids()
			queue_redraw()
	_text_plan_pending = _text_worker.has_pending_work()


func _on_image_texture_ready(asset_id: String) -> void:
	if _image_renderer != null:
		_image_renderer.notify_texture_ready(asset_id)
	queue_redraw()


func _on_pdf_page_ready(asset_id: String, page_index: int) -> void:
	if _pdf_renderer != null:
		_pdf_renderer.notify_page_ready(asset_id, page_index)
	queue_redraw()


func _on_pdf_page_failed(_asset_id: String, _page_index: int, _message: String) -> void:
	# The retained PDF layer needs one redraw so the placeholder immediately
	# reflects a Poppler/render failure instead of waiting for unrelated input.
	if _pdf_renderer != null:
		_pdf_renderer.queue_redraw()
	queue_redraw()


func _on_formula_texture_ready(cache_key: String) -> void:
	if _formula_renderer != null:
		_formula_renderer.notify_texture_ready(cache_key)
	if _note_portal_renderer != null:
		_note_portal_renderer.queue_redraw()
	queue_redraw()


func _on_formula_render_failed(_cache_key: String, _message: String, _detail: String) -> void:
	if _formula_renderer != null:
		_formula_renderer.queue_redraw()
	if _note_portal_renderer != null:
		_note_portal_renderer.queue_redraw()
	queue_redraw()


func _on_video_thumbnail_ready(asset_id: String) -> void:
	if _video_renderer != null:
		_video_renderer.notify_thumbnail_ready(asset_id)
	queue_redraw()


func _on_audio_waveform_ready(asset_id: String) -> void:
	if _audio_renderer != null:
		_audio_renderer.notify_waveform_ready(asset_id)
	queue_redraw()


func _on_stroke_renderer_handoff_ready(ready_entity_ids: PackedInt64Array) -> void:
	if _stroke_commit_handoff_ids.is_empty() or ready_entity_ids.is_empty():
		return
	# The signal is emitted from StrokeBatchRenderer._draw(). Never release the
	# transient owner while a canvas draw pass is still in progress: depending on
	# CanvasItem ordering that can create a one-frame hole. Finalize on idle, after
	# the current frame has safely presented the transient stroke.
	call_deferred("_finalize_stroke_renderer_handoff", ready_entity_ids.duplicate())


func _finalize_stroke_renderer_handoff(ready_entity_ids: PackedInt64Array) -> void:
	if _stroke_commit_handoff_ids.is_empty() or ready_entity_ids.is_empty():
		return
	var ready_lookup: Dictionary = {}
	for entity_id: int in ready_entity_ids:
		ready_lookup[entity_id] = true
	var changed: bool = false
	for raw_id: Variant in _stroke_commit_handoff_ids.keys():
		var entity_id: int = int(raw_id)
		if ready_lookup.has(entity_id):
			_stroke_commit_handoff_ids.erase(raw_id)
			changed = true
	if changed:
		_sync_stroke_renderer_handoff_watch()
		# The retained renderer deliberately skipped watched strokes in its previous
		# draw pass, so it must redraw immediately after ownership transfers. The
		# parent redraw removes the transient copy in the same presentation frame.
		if _stroke_renderer != null:
			_stroke_renderer.queue_redraw()
		queue_redraw()


func _prune_commit_handoff_ids() -> void:
	if _runtime == null:
		_text_commit_handoff_ids.clear()
		_stroke_commit_handoff_ids.clear()
		_sync_stroke_renderer_handoff_watch()
		return
	for raw_id: Variant in _text_commit_handoff_ids.keys():
		if not _runtime.model.text_blocks.contains(int(raw_id)):
			_text_commit_handoff_ids.erase(raw_id)
	var stroke_watch_changed: bool = false
	for raw_id: Variant in _stroke_commit_handoff_ids.keys():
		if not _runtime.model.strokes.contains(int(raw_id)):
			_stroke_commit_handoff_ids.erase(raw_id)
			stroke_watch_changed = true
	if stroke_watch_changed:
		_sync_stroke_renderer_handoff_watch()


func _queue_changed_model_refreshes() -> void:
	if _runtime == null:
		return
	var refresh_mask: int = 0
	if _render_model_revision != _runtime.model.text_revision:
		refresh_mask |= RENDER_REFRESH_TEXT
	if _image_model_revision != _runtime.model.image_revision:
		refresh_mask |= RENDER_REFRESH_IMAGE
	if _pdf_model_revision != _runtime.model.pdf_revision:
		refresh_mask |= RENDER_REFRESH_PDF
	if _formula_model_revision != _runtime.model.formula_revision:
		refresh_mask |= RENDER_REFRESH_FORMULA
	if _video_model_revision != _runtime.model.video_revision:
		refresh_mask |= RENDER_REFRESH_VIDEO
	if _audio_model_revision != _runtime.model.audio_revision:
		refresh_mask |= RENDER_REFRESH_AUDIO
	if _note_portal_model_revision != _runtime.model.note_portal_revision:
		refresh_mask |= RENDER_REFRESH_NOTE_PORTAL
	if _stroke_model_revision != _runtime.model.stroke_revision:
		refresh_mask |= RENDER_REFRESH_STROKE
	if _connector_model_revision != _runtime.model.connector_revision:
		refresh_mask |= RENDER_REFRESH_CONNECTOR
	if refresh_mask == 0:
		return
	_render_pending_mask |= refresh_mask
	_render_model_pending_mask |= refresh_mask
	set_process(true)


func _on_note_repository_visual_changed(_note_id: String) -> void:
	_request_note_portal_refresh(true)
	queue_redraw()


func _on_note_repository_notes_changed() -> void:
	_request_note_portal_refresh(true)
	queue_redraw()


func _on_runtime_changed() -> void:
	_prune_commit_handoff_ids()
	if _stroke_handoff_renderer != null and not _stroke_commit_handoff_ids.is_empty():
		_stroke_handoff_renderer.queue_redraw()
	if _pointer_action == ACTION_MOVE or _pointer_action == ACTION_RESIZE:
		queue_redraw()
		return
	# The active editor is rendered transiently and intentionally excluded from the
	# retained text plan. Avoid rebuilding every visible text block on each keystroke.
	if _editing_entity_id > 0:
		queue_redraw()
		_emit_context_anchor()
		return
	# Preserve model-dirty work independently from viewport/LOD refreshes. Camera
	# input is allowed to discard stale view work, but it must never discard a
	# revision change for an object type; doing so made retained content appear only
	# after the next unrelated edit. Only categories whose revisions changed are
	# queued, which also keeps a newly committed stroke from waking every renderer.
	_queue_changed_model_refreshes()
	queue_redraw()
	_emit_context_anchor()


func _on_selection_changed(_selected_ids: PackedInt64Array, _primary_id: int) -> void:
	queue_redraw()
	_emit_context_anchor()


func _on_resized() -> void:
	_sync_camera_visuals()
	_mark_view_dirty()
	queue_redraw()
	_emit_context_anchor()


func _set_context_ui_suppressed(value: bool) -> void:
	if value:
		_context_anchor_dirty = true
		if _context_ui_suppressed:
			return
		_context_ui_suppressed = true
		if _telemetry != null:
			_telemetry.record_developer_counter(&"context_hides")
		_publish_context_anchor(Rect2(), false)
		return
	var should_restore: bool = _context_ui_suppressed or _context_anchor_dirty
	_context_ui_suppressed = false
	if should_restore:
		_context_anchor_dirty = false
		if _telemetry != null:
			_telemetry.record_developer_counter(&"context_restores")
		_emit_context_anchor(true)


func _emit_context_anchor(force: bool = false) -> void:
	if _context_ui_suppressed:
		_context_anchor_dirty = true
		return
	_context_anchor_dirty = false
	if _runtime == null or _runtime.selection.size() == 0:
		_publish_context_anchor(Rect2(), false, force)
		return
	if _editing_entity_id > 0 and _runtime.model.contains(_editing_entity_id):
		var editor_rect: Rect2 = Rect2(
			world_to_screen(_editing_preview_bounds.position),
			_editing_preview_bounds.size * zoom
		)
		_publish_context_anchor(editor_rect, editor_rect.has_area(), force)
		return
	var selected_ids: PackedInt64Array = _runtime.selection.get_selected_ids()
	var has_rect: bool = false
	var combined: Rect2 = Rect2()
	for entity_id: int in selected_ids:
		if not _runtime.model.contains(entity_id):
			continue
		var bounds: Rect2 = _runtime.model.get_entity_bounds(entity_id)
		var screen_rect: Rect2 = Rect2(world_to_screen(bounds.position), bounds.size * zoom)
		combined = combined.merge(screen_rect) if has_rect else screen_rect
		has_rect = true
	_publish_context_anchor(combined, has_rect, force)


func _publish_context_anchor(screen_rect: Rect2, should_show: bool, force: bool = false) -> void:
	if (
		not force
		and _context_signal_initialized
		and _last_context_anchor_visible == should_show
		and (not should_show or _last_context_anchor_rect == screen_rect)
	):
		return
	_context_signal_initialized = true
	_last_context_anchor_rect = screen_rect
	_last_context_anchor_visible = should_show
	context_anchor_changed.emit(screen_rect, should_show)


func refresh_palette() -> void:
	if _grid_renderer != null:
		_grid_renderer.refresh_palette()
	if _stroke_renderer != null:
		_stroke_renderer.queue_redraw()
	queue_redraw()


func _default_cursor() -> Control.CursorShape:
	match _active_tool_id:
		BoardToolController.TOOL_HAND:
			return Control.CURSOR_DRAG
		BoardToolController.TOOL_TEXT:
			# Keep the native I-beam untouched for real TextEdit/LineEdit controls.
			# The board text-placement tool uses its own hardware cursor shape.
			return Control.CURSOR_VSPLIT
		BoardToolController.TOOL_DRAW:
			return Control.CURSOR_CROSS
		BoardToolController.TOOL_FORMULA:
			return Control.CURSOR_HELP
		_:
			return Control.CURSOR_ARROW


func _needs_overlay_redraw() -> bool:
	return (
		_hover_entity_id > 0
		or _pointer_action != ACTION_NONE
		or _editing_entity_id > 0
		or not _text_commit_handoff_ids.is_empty()
		or (_runtime != null and _runtime.selection.size() > 0)
		or _has_inactive_module_cards()
	)


func _has_inactive_module_cards() -> bool:
	# Inactive ModuleObjects are drawn by this Control in screen space rather than
	# by BoardWorld. CanvasItem custom drawing is cached until queue_redraw(), so a
	# camera-only pan/zoom must invalidate it even when there is no hover/selection.
	# Otherwise the cached placeholder appears pinned to the viewport until the next
	# mouse event triggers a redraw. Live module surfaces are excluded here because
	# their Controls are positioned explicitly by ModuleSurfacePool.
	if _runtime == null or _runtime.model.modules.size() <= 0:
		return false
	for entity_id: int in _runtime.model.modules.entity_ids:
		if not _runtime.model.contains(entity_id):
			continue
		if _hidden_render_ids.has(entity_id) or _live_module_surface_ids.has(entity_id):
			continue
		return true
	return false


func _begin_content_handoff_quiet_window() -> void:
	# Pointer actions keep retained work deferred while they are active. Reset the
	# same quiet-window clock at commit time so the first frame after mouse-up or
	# editor close is never spent rebuilding a large retained batch. Model revision
	# work is marked separately so a pan/zoom cannot discard it as stale view work.
	_interaction_idle_seconds = 0.0
	_queue_changed_model_refreshes()
	set_process(true)


func _mark_view_dirty() -> void:
	interaction_activity.emit()
	_view_dirty = true
	_view_render_dirty = true
	_interaction_idle_seconds = 0.0
	# Camera interaction invalidates only stale viewport/LOD work. Forced refreshes
	# and category revisions caused by actual model changes must survive; otherwise
	# a quick pan immediately after an edit can erase the only pending retained
	# rebuild for that edit.
	var durable_mask: int = _render_force_mask | _render_model_pending_mask
	var dropped_view_mask: int = _render_pending_mask & ~durable_mask
	_render_pending_mask &= durable_mask
	if dropped_view_mask != 0 and _telemetry != null:
		_telemetry.record_developer_counter(&"render_stale_view_drops")
	set_process(true)


func _emit_view_state() -> void:
	_view_dirty = false
	view_state_changed.emit(get_view_state())


func _mark_interaction() -> void:
	if _has_interacted:
		return
	_has_interacted = true
	first_interaction.emit()


func _emit_zoom_if_needed(force: bool) -> void:
	var zoom_percent: int = int(round(zoom * 100.0))
	if not force and zoom_percent == _last_emitted_zoom_percent:
		return
	_last_emitted_zoom_percent = zoom_percent
	zoom_changed.emit(zoom)
