# SPDX-License-Identifier: GPL-3.0-or-later
class_name BoardScreen
extends Control

signal back_requested

var session: BoardSession
var settings: AppSettingsStore
var asset_library: AssetLibraryService
var image_cache: ImageAssetCache
var pdf_media: PdfMediaService
var pdf_optimizer: PdfOptimizationService
var video_media: VideoMediaService
var audio_media: AudioMediaService
var app_audio: AppAudioService
var voice_recording: VoiceRecordingService
var formula_render: FormulaRenderService
var power_status: PowerStatusService
var module_registry: ModuleRegistry
var note_repository: NoteRepository
var telemetry: PerformanceTelemetryService
var repository: BoardRepository
var _board_view: NativeBoardView
var _video_player_pool: VideoPlayerPool
var _audio_player_pool: AudioPlayerPool
var _title_button: Button
var _zoom_label: Label
var _zoom_reset_button: Button
var _monitor_strip: PerformanceMonitorStrip
var _developer_panel: DeveloperDiagnosticsPanel
var _status_panel: PanelContainer
var _monitor_panel: PanelContainer
var _developer_panel_container: PanelContainer
var _hint_panel: PanelContainer
var _hint_label: Label
var _welcome_panel: PanelContainer
var _rename_dialog: NameDialog
var _asset_rename_dialog: NameDialog
var _image_import_dialog: FileDialog
var _pdf_import_dialog: FileDialog
var _video_import_dialog: FileDialog
var _audio_import_dialog: FileDialog
var _settings_dialog: SettingsDialog
var _microphone_permission_dialog: MicrophonePermissionDialog
var _error_panel: PanelContainer
var _error_label: Label
var _error_timer: Timer
var _hand_button: Button
var _select_button: Button
var _text_button: Button
var _draw_button: Button
var _formula_button: Button
var _image_import_button: Button
var _pdf_import_button: Button
var _video_import_button: Button
var _audio_import_button: Button
var _voice_record_button: Button
var _tool_rail: PanelContainer
var _utility_panel: PanelContainer
var _text_toolbar: TextContextToolbar
var _connector_toolbar: ConnectorContextToolbar
var _image_toolbar: ImageContextToolbar
var _pdf_toolbar: PdfContextToolbar
var _video_toolbar: VideoContextToolbar
var _audio_toolbar: AudioContextToolbar
var _stroke_toolbar: StrokeContextToolbar
var _formula_toolbar: FormulaContextToolbar
var _drawing_palette: DrawingToolPalette
var _color_popover: BoardColorPopover
var _formula_editor: FormulaEditorPanel
var _formula_new_world_position: Vector2 = Vector2.ZERO
var _formula_edit_entity_id: int = 0
var _color_popover_mode: int = 0
var _editing_text_entity_id: int = 0
var _text_toolbar_anchor: Rect2 = Rect2()
var _text_toolbar_should_show: bool = false
var _undo_button: Button
var _redo_button: Button
var _settings_button: Button
var _save_button: Button
var _library_button: Button
var _notes_button: Button
var _module_button: Button
var _library_drawer: PanelContainer
var _asset_view: AssetLibraryView
var _asset_preview: AssetPreviewOverlay
var _notes_workspace: NoteWorkspaceOverlay
var _library_drawer_open: bool = false
var _library_drawer_tween: Tween
var _module_picker: ModulePickerPanel
var _module_picker_open: bool = false
var _module_picker_tween: Tween
var _module_surface_pool: ModuleSurfacePool
var _note_surface_pool: NoteBoardSurfacePool
var _board_search_panel: BoardSearchPanel
var _board_search_snapshot_dirty: bool = true
var _board_search_snapshot_signature: String = ""
var _board_display_name: String = NotLightL10n.text("modules.library.board_fallback")
var _save_state: BoardSession.SaveState = BoardSession.SaveState.CLOSED
var _pending_image_jobs: Dictionary = {}
var _pending_pdf_jobs: Dictionary = {}
var _pending_pdf_placements: Dictionary = {}
var _pending_video_jobs: Dictionary = {}
var _pending_audio_jobs: Dictionary = {}
var _pending_note_jobs: Dictionary = {}
var _pending_voice_jobs: Dictionary = {}
var _pending_asset_placements: Dictionary = {}
var _pending_rename_entity_id: int = 0
var _image_import_target_world: Vector2 = Vector2.ZERO
var _pdf_import_target_world: Vector2 = Vector2.ZERO
var _video_import_target_world: Vector2 = Vector2.ZERO
var _audio_import_target_world: Vector2 = Vector2.ZERO
var _voice_record_target_world: Vector2 = Vector2.ZERO
var _voice_record_panel: PanelContainer
var _voice_record_label: Label
var _voice_record_timer: Timer

const COLOR_POPOVER_NONE: int = 0
const COLOR_POPOVER_TEXT: int = 1
const COLOR_POPOVER_BACKGROUND: int = 2
const COLOR_POPOVER_CONNECTOR: int = 3
const COLOR_POPOVER_DRAWING: int = 4
const COLOR_POPOVER_STROKE: int = 5
const COLOR_POPOVER_FORMULA_EDITOR: int = 6
const COLOR_POPOVER_FORMULA_OBJECT: int = 7


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	_build_ui()
	_build_rename_dialog()
	_build_asset_rename_dialog()
	_build_image_import_dialog()
	_build_pdf_import_dialog()
	_build_video_import_dialog()
	_build_audio_import_dialog()
	_build_settings_dialog()
	_build_microphone_permission_dialog()
	_build_error_message()
	resized.connect(_update_bottom_layout)
	call_deferred("_update_bottom_layout")



func _exit_tree() -> void:
	if voice_recording != null and voice_recording.is_recording():
		voice_recording.cancel_recording()
	if telemetry != null:
		telemetry.set_developer_context_provider(Callable())
	var window: Window = get_window()
	if window != null and window.files_dropped.is_connected(_on_files_dropped):
		window.files_dropped.disconnect(_on_files_dropped)


func configure(
	board_session: BoardSession,
	app_settings: AppSettingsStore,
	library_service: AssetLibraryService,
	cache: ImageAssetCache = null,
	pdf_service: PdfMediaService = null,
	media: VideoMediaService = null,
	audio_service: AudioMediaService = null,
	voice_service: VoiceRecordingService = null,
	telemetry_service: PerformanceTelemetryService = null,
	pdf_optimization_service: PdfOptimizationService = null,
	formula_service: FormulaRenderService = null,
	power_service: PowerStatusService = null,
	module_registry_service: ModuleRegistry = null,
	note_repository_service: NoteRepository = null,
	app_audio_service: AppAudioService = null,
	board_repository_service: BoardRepository = null
) -> void:
	session = board_session
	settings = app_settings
	asset_library = library_service
	image_cache = cache
	pdf_media = pdf_service
	pdf_optimizer = pdf_optimization_service
	video_media = media
	audio_media = audio_service
	voice_recording = voice_service
	formula_render = formula_service
	power_status = power_service
	module_registry = module_registry_service
	note_repository = note_repository_service
	app_audio = app_audio_service
	repository = board_repository_service
	telemetry = telemetry_service
	if telemetry != null:
		telemetry.set_developer_context_provider(Callable(self, "_developer_diagnostics_context"))
	if not session.metadata_changed.is_connected(_on_metadata_changed):
		session.metadata_changed.connect(_on_metadata_changed)
	if not session.save_state_changed.is_connected(_on_save_state_changed):
		session.save_state_changed.connect(_on_save_state_changed)
	if not session.runtime.commands.history_changed.is_connected(_on_history_changed):
		session.runtime.commands.history_changed.connect(_on_history_changed)
	if not session.runtime.tools.active_tool_changed.is_connected(_on_active_tool_changed):
		session.runtime.tools.active_tool_changed.connect(_on_active_tool_changed)
	if not session.runtime.selection.selection_changed.is_connected(_on_selection_context_changed):
		session.runtime.selection.selection_changed.connect(_on_selection_context_changed)
	if not session.runtime.runtime_changed.is_connected(_on_runtime_context_changed):
		session.runtime.runtime_changed.connect(_on_runtime_context_changed)
	if not settings.settings_changed.is_connected(_on_settings_changed):
		settings.settings_changed.connect(_on_settings_changed)
	if not settings.settings_error.is_connected(_show_error):
		settings.settings_error.connect(_show_error)
	if not _board_view.interaction_activity.is_connected(_on_board_interaction_activity):
		_board_view.interaction_activity.connect(_on_board_interaction_activity)
	_settings_dialog.configure(settings, asset_library, video_media, false, module_registry, app_audio, repository)
	settings.apply_render_policy(session.runtime.render_policy)
	if _asset_view != null and asset_library != null:
		_asset_view.configure(asset_library, image_cache, video_media, settings, audio_media, null, pdf_media, pdf_optimizer)
	if _asset_preview != null and asset_library != null:
		_asset_preview.configure(asset_library, image_cache, video_media, audio_media, pdf_media)
	if _notes_workspace != null:
		_notes_workspace.configure(note_repository, true, formula_render, settings, asset_library, image_cache, video_media, audio_media, pdf_media, module_registry)
	if _monitor_strip != null:
		_monitor_strip.configure(settings, telemetry, power_status)
	if _developer_panel != null:
		_developer_panel.configure(settings, telemetry)
	if _drawing_palette != null:
		_drawing_palette.configure(settings)
		var brush: Dictionary = settings.get_drawing_brush_snapshot()
		var brush_color_value: Variant = brush.get("color", Color("#245cff"))
		var brush_color: Color = brush_color_value if brush_color_value is Color else Color("#245cff")
		_board_view.set_drawing_brush(
			int(brush.get("style", StrokeStore.STYLE_PEN)),
			brush_color,
			float(brush.get("width", 4.0)),
			float(brush.get("spray_spread", 1.0)),
			false,
			float(brush.get("eraser_radius", 18.0))
		)
	if asset_library != null:
		if not asset_library.library_changed.is_connected(_refresh_context_toolbars):
			asset_library.library_changed.connect(_refresh_context_toolbars)
		if not asset_library.library_changed.is_connected(_mark_board_search_snapshot_dirty):
			asset_library.library_changed.connect(_mark_board_search_snapshot_dirty)
		if not asset_library.import_job_finished.is_connected(_on_import_job_finished):
			asset_library.import_job_finished.connect(_on_import_job_finished)
		if not asset_library.import_job_failed.is_connected(_on_import_job_failed):
			asset_library.import_job_failed.connect(_on_import_job_failed)
	if image_cache != null:
		if not image_cache.texture_ready.is_connected(_on_image_texture_ready):
			image_cache.texture_ready.connect(_on_image_texture_ready)
		if not image_cache.texture_failed.is_connected(_on_image_texture_failed):
			image_cache.texture_failed.connect(_on_image_texture_failed)
	if pdf_media != null:
		if not pdf_media.document_ready.is_connected(_on_pdf_document_ready):
			pdf_media.document_ready.connect(_on_pdf_document_ready)
		if not pdf_media.preparation_failed.is_connected(_on_pdf_preparation_failed):
			pdf_media.preparation_failed.connect(_on_pdf_preparation_failed)
	if audio_media != null:
		if not audio_media.preparation_failed.is_connected(_on_audio_preparation_failed):
			audio_media.preparation_failed.connect(_on_audio_preparation_failed)
		if not audio_media.playback_ready.is_connected(_on_audio_playback_ready):
			audio_media.playback_ready.connect(_on_audio_playback_ready)
	if voice_recording != null:
		if not voice_recording.recording_started.is_connected(_on_voice_recording_started):
			voice_recording.recording_started.connect(_on_voice_recording_started)
		if not voice_recording.recording_cancelled.is_connected(_on_voice_recording_cancelled):
			voice_recording.recording_cancelled.connect(_on_voice_recording_cancelled)
		if not voice_recording.recording_failed.is_connected(_on_voice_recording_failed):
			voice_recording.recording_failed.connect(_on_voice_recording_failed)
		if not voice_recording.voice_import_finished.is_connected(_on_voice_import_finished):
			voice_recording.voice_import_finished.connect(_on_voice_import_finished)
		if not voice_recording.voice_import_failed.is_connected(_on_voice_import_failed):
			voice_recording.voice_import_failed.connect(_on_voice_import_failed)
	_board_view.configure_telemetry(telemetry)
	_board_view.configure_runtime(session.runtime)
	_mark_board_search_snapshot_dirty()
	if telemetry != null:
		telemetry.reset_developer_session()
	_board_view.configure_image_cache(image_cache)
	_board_view.configure_pdf_media(pdf_media)
	_board_view.configure_formula_render(formula_render)
	_board_view.configure_video_media(video_media)
	_board_view.configure_audio_media(audio_media)
	_board_view.configure_module_registry(module_registry)
	_board_view.configure_note_repository(note_repository)
	if _module_picker != null:
		_module_picker.configure(module_registry)
	if _module_surface_pool != null:
		_module_surface_pool.configure(_board_view, session, module_registry, _active_module_budget())
	if _note_surface_pool != null:
		_note_surface_pool.configure(_board_view, session, note_repository, formula_render, settings, asset_library, image_cache, video_media, audio_media, pdf_media, module_registry, _active_note_workspace_budget())
	if _formula_editor != null:
		_formula_editor.configure(formula_render)
	if _video_player_pool != null:
		_video_player_pool.configure(_board_view, video_media, asset_library, _active_video_budget())
	if _audio_player_pool != null:
		_audio_player_pool.configure(_board_view, audio_media, asset_library, _active_audio_budget())
	var window: Window = get_window()
	if window != null and not window.files_dropped.is_connected(_on_files_dropped):
		window.files_dropped.connect(_on_files_dropped)
	_board_view.apply_settings(settings.get_snapshot())
	_board_view.set_active_tool(session.runtime.tools.active_tool_id)
	var view_state: Dictionary = session.get_view_state()
	_board_view.set_view_state(view_state)
	var camera_data: Dictionary = view_state.get("camera_position", {}) as Dictionary
	var restored_position: Vector2 = Vector2(
		float(camera_data.get("x", 0.0)),
		float(camera_data.get("y", 0.0))
	)
	if (
		not restored_position.is_zero_approx()
		or not is_equal_approx(float(view_state.get("zoom", 1.0)), 1.0)
		or session.runtime.model.text_blocks.size() > 0
		or session.runtime.model.images.size() > 0
		or session.runtime.model.pdfs.size() > 0
		or session.runtime.model.formulas.size() > 0
		or session.runtime.model.videos.size() > 0
		or session.runtime.model.audios.size() > 0
		or session.runtime.model.modules.size() > 0
		or session.runtime.model.note_portals.size() > 0
		or session.runtime.model.strokes.size() > 0
	):
		_welcome_panel.visible = false
	_on_metadata_changed(session.metadata)
	_on_save_state_changed(session.save_state, NotLightL10n.text("library.inspector.saved"))
	_on_history_changed(false, false, "", "")
	_on_active_tool_changed(session.runtime.tools.active_tool_id)
	_on_settings_changed(settings.get_snapshot())
	_refresh_text_toolbar()


func _input(event: InputEvent) -> void:
	if _asset_preview != null and _asset_preview.visible:
		return
	# Ctrl/Command+F is a board-level shortcut and must win even when an inline
	# text editor or LineEdit currently owns GUI focus. _input runs before the GUI
	# consumes text-editing shortcuts; every other key stays on the normal path.
	if event is not InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if (key_event.ctrl_pressed or key_event.meta_pressed) and key_event.keycode == KEY_F:
		_toggle_board_search()
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if _asset_preview != null and _asset_preview.visible:
		return
	if _notes_workspace != null and _notes_workspace.visible:
		return
	if event is not InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var command_modifier: bool = key_event.ctrl_pressed or key_event.meta_pressed
	# Ctrl/Command+F is captured in _input() so focused LineEdit/TextEdit controls
	# cannot swallow it. Escape remains here because the focused search LineEdit
	# does not consume it before unhandled key input.
	if key_event.keycode == KEY_ESCAPE and _board_search_panel != null and _board_search_panel.is_open():
		_board_search_panel.close_panel()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_ESCAPE and _module_picker_open:
		_set_module_picker_open(false)
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_ESCAPE and _color_popover != null and _color_popover.visible:
		_close_color_popover()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_ESCAPE and _formula_editor != null and _formula_editor.visible:
		_discard_formula_draft()
		get_viewport().set_input_as_handled()
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	if key_event.keycode == KEY_ESCAPE:
		if _formula_editor != null and _formula_editor.visible:
			_discard_formula_draft()
		elif _library_drawer_open:
			_set_library_drawer_open(false)
		elif _settings_dialog != null and _settings_dialog.visible:
			_settings_dialog.close_dialog()
		else:
			_open_settings_dialog()
		get_viewport().set_input_as_handled()
		return
	if command_modifier and key_event.keycode == KEY_C:
		_board_view.copy_selection()
		get_viewport().set_input_as_handled()
		return
	if command_modifier and key_event.keycode == KEY_V:
		_paste_from_system_clipboard()
		get_viewport().set_input_as_handled()
		return
	if command_modifier and key_event.keycode == KEY_D:
		_board_view.duplicate_selection()
		get_viewport().set_input_as_handled()
		return
	if command_modifier and key_event.keycode == KEY_S:
		_save_now()
		get_viewport().set_input_as_handled()
		return
	if command_modifier and key_event.keycode == KEY_Z:
		_board_view.commit_active_editor()
		if session != null:
			if key_event.shift_pressed:
				session.redo()
			else:
				session.undo()
		get_viewport().set_input_as_handled()
		return
	if command_modifier and key_event.keycode == KEY_Y:
		_board_view.commit_active_editor()
		if session != null:
			session.redo()
		get_viewport().set_input_as_handled()
		return
	if not command_modifier:
		match key_event.keycode:
			KEY_L:
				_set_library_drawer_open(not _library_drawer_open)
			KEY_N:
				_open_notes_browser()
			KEY_V, KEY_1:
				_set_active_tool(BoardToolController.TOOL_SELECT)
			KEY_H, KEY_2:
				_set_active_tool(BoardToolController.TOOL_HAND)
			KEY_T, KEY_3:
				_set_active_tool(BoardToolController.TOOL_TEXT)
			KEY_B, KEY_4:
				_set_active_tool(BoardToolController.TOOL_DRAW)
			KEY_M, KEY_5:
				_set_active_tool(BoardToolController.TOOL_FORMULA)
			KEY_I:
				_open_image_import_dialog()
			KEY_F:
				if not _board_view.focus_single_selection():
					return
			_:
				return
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_board_view = NativeBoardView.new()
	_board_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board_view.view_state_changed.connect(_on_view_state_changed)
	_board_view.zoom_changed.connect(_on_zoom_changed)
	_board_view.first_interaction.connect(_hide_welcome)
	_board_view.text_editor_state_changed.connect(_on_text_editor_state_changed)
	_board_view.text_editor_format_changed.connect(_on_text_editor_format_changed)
	_board_view.context_anchor_changed.connect(_on_context_anchor_changed)
	_board_view.video_open_requested.connect(_open_board_video)
	_board_view.audio_open_requested.connect(_open_board_audio)
	_board_view.formula_create_requested.connect(_on_formula_create_requested)
	_board_view.formula_edit_requested.connect(_on_formula_edit_requested)
	_board_view.module_open_requested.connect(_on_module_open_requested)
	_board_view.note_open_requested.connect(_open_board_note)
	add_child(_board_view)
	_build_module_surface_pool()
	_build_note_surface_pool()
	_build_welcome_panel()
	_build_top_bar()
	_build_tool_rail()
	_build_board_utilities()
	_build_asset_library_drawer()
	_build_module_picker()
	_build_board_search_panel()
	_build_text_context_toolbar()
	_build_connector_context_toolbar()
	_build_image_context_toolbar()
	_build_pdf_context_toolbar()
	_build_video_context_toolbar()
	_build_audio_context_toolbar()
	_build_stroke_context_toolbar()
	_build_formula_context_toolbar()
	_build_drawing_palette()
	_build_color_popover()
	_build_formula_editor_panel()
	_build_status_controls()
	_build_hint()
	_build_video_player()
	_build_audio_player()
	_build_voice_recording_panel()
	_asset_preview = AssetPreviewOverlay.new()
	_asset_preview.closed.connect(_on_asset_preview_closed)
	add_child(_asset_preview)
	_notes_workspace = NoteWorkspaceOverlay.new()
	_notes_workspace.closed.connect(_on_notes_workspace_closed)
	_notes_workspace.note_insert_requested.connect(_place_note_from_workspace)
	_notes_workspace.note_workspace_insert_requested.connect(_place_note_workspace_from_workspace)
	_notes_workspace.error_requested.connect(_show_error)
	_notes_workspace.asset_preview_requested.connect(_open_asset_preview)
	add_child(_notes_workspace)


func _open_asset_preview(asset_id: String) -> void:
	if asset_library != null:
		var asset: Dictionary = asset_library.get_asset(asset_id)
		if int(asset.get("kind", AssetKinds.OTHER)) == AssetKinds.NOTE:
			_open_board_note(asset_id, 0)
			return
	if _asset_preview == null:
		return
	_asset_preview.open_asset(asset_id)
	if _asset_preview.visible:
		_board_view.set_process_unhandled_key_input(false)


func _on_asset_preview_closed() -> void:
	if _board_view != null and (_notes_workspace == null or not _notes_workspace.visible):
		_board_view.set_process_unhandled_key_input(true)


func _open_notes_browser() -> void:
	if _notes_workspace == null or note_repository == null:
		_show_error(NotLightL10n.text("notes.error.unavailable"))
		return
	_set_library_drawer_open(false)
	_set_module_picker_open(false)
	_notes_workspace.open_browser()
	_board_view.set_process_unhandled_key_input(false)


func _open_notes_graph() -> void:
	if _notes_workspace == null or note_repository == null:
		_show_error(NotLightL10n.text("notes.error.unavailable"))
		return
	_set_library_drawer_open(false)
	_set_module_picker_open(false)
	_notes_workspace.open_graph()
	_board_view.set_process_unhandled_key_input(false)


func _open_board_note(note_id: String, entity_id: int) -> void:
	if (
		entity_id > 0
		and session != null
		and session.runtime.model.note_portals.contains(entity_id)
		and session.runtime.model.note_portals.get_view_mode(entity_id) == NotePortalStore.VIEW_WORKSPACE
		and _note_surface_pool != null
	):
		if not _note_surface_pool.activate(entity_id):
			_show_error(NotLightL10n.text("notes.workspace.activate_failed"))
		return
	if _notes_workspace == null or note_repository == null:
		_show_error(NotLightL10n.text("notes.error.unavailable"))
		return
	if not note_repository.contains(note_id):
		_show_error(NotLightL10n.text("notes.error.missing"))
		return
	_notes_workspace.open_note(note_id)
	_board_view.set_process_unhandled_key_input(false)


func _on_notes_workspace_closed() -> void:
	if _board_view != null and (_asset_preview == null or not _asset_preview.visible):
		_board_view.set_process_unhandled_key_input(true)


func _place_note_from_workspace(note_id: String) -> void:
	_place_note_portal(note_id, _board_view.get_view_center_world_position(), NotePortalStore.VIEW_PREVIEW)


func _place_note_workspace_from_workspace(note_id: String) -> void:
	var entity_id: int = _place_note_portal(note_id, _board_view.get_view_center_world_position(), NotePortalStore.VIEW_WORKSPACE)
	if entity_id > 0 and _note_surface_pool != null:
		_note_surface_pool.activate(entity_id)


func _build_video_player() -> void:
	_video_player_pool = VideoPlayerPool.new()
	_video_player_pool.name = "VideoPlayerPool"
	_video_player_pool.message_requested.connect(_show_error)
	add_child(_video_player_pool)
	if video_media != null:
		_video_player_pool.configure(_board_view, video_media, asset_library, _active_video_budget())


func _build_audio_player() -> void:
	_audio_player_pool = AudioPlayerPool.new()
	_audio_player_pool.name = "AudioPlayerPool"
	_audio_player_pool.message_requested.connect(_show_error)
	add_child(_audio_player_pool)
	if audio_media != null:
		_audio_player_pool.configure(_board_view, audio_media, asset_library, _active_audio_budget())


func _build_voice_recording_panel() -> void:
	_voice_record_panel = PanelContainer.new()
	_voice_record_panel.name = "VoiceRecordingPanel"
	_voice_record_panel.theme_type_variation = "FloatingPanel"
	_voice_record_panel.z_index = 620
	_voice_record_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_voice_record_panel.offset_left = -190.0
	_voice_record_panel.offset_top = 88.0
	_voice_record_panel.offset_right = 190.0
	_voice_record_panel.offset_bottom = 144.0
	_voice_record_panel.visible = false
	add_child(_voice_record_panel)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_voice_record_panel.add_child(row)
	var dot: Label = Label.new()
	dot.text = "●"
	NotLightL10n.bind_tooltip(dot, "voice.recording_indicator")
	dot.add_theme_color_override("font_color", NotLightTheme.semantic_color("danger"))
	dot.custom_minimum_size = Vector2(24.0, 36.0)
	dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(dot)
	_voice_record_label = Label.new()
	_voice_record_label.text = NotLightL10n.text("voice.recording_label", {"time": NotLightL10n.text("ui.format.time_zero")})
	_voice_record_label.theme_type_variation = "CaptionStrongLabel"
	_voice_record_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_voice_record_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_voice_record_label)
	var stop_button: Button = Button.new()
	NotLightL10n.bind_text(stop_button, "voice.stop")
	NotLightL10n.bind_tooltip(stop_button, "voice.stop_help")
	stop_button.theme_type_variation = "AccentButton"
	stop_button.custom_minimum_size = Vector2(72.0, 36.0)
	stop_button.pressed.connect(_stop_voice_recording)
	row.add_child(stop_button)
	var cancel_button: Button = Button.new()
	NotLightL10n.bind_text(cancel_button, "common.cancel")
	NotLightL10n.bind_tooltip(cancel_button, "voice.cancel_help")
	cancel_button.theme_type_variation = "GhostButton"
	cancel_button.custom_minimum_size = Vector2(74.0, 36.0)
	cancel_button.pressed.connect(_cancel_voice_recording)
	row.add_child(cancel_button)
	_voice_record_timer = Timer.new()
	_voice_record_timer.wait_time = 0.2
	_voice_record_timer.one_shot = false
	_voice_record_timer.timeout.connect(_refresh_voice_recording_label)
	add_child(_voice_record_timer)


func _build_top_bar() -> void:
	var top_panel: PanelContainer = PanelContainer.new()
	top_panel.theme_type_variation = "FloatingPanel"
	top_panel.z_index = 300
	top_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top_panel.offset_left = 18.0
	top_panel.offset_top = 16.0
	top_panel.offset_right = 366.0
	top_panel.offset_bottom = 70.0
	add_child(top_panel)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	top_panel.add_child(row)
	var back_button: Button = Button.new()
	back_button.icon = load("res://assets/icons/arrow_left.svg") as Texture2D
	NotLightL10n.bind_tooltip(back_button, "runtime.ui.board_screen.104cd30ead")
	back_button.theme_type_variation = "IconButton"
	back_button.custom_minimum_size = Vector2(40.0, 38.0)
	back_button.pressed.connect(_request_back)
	row.add_child(back_button)
	var divider: VSeparator = VSeparator.new()
	divider.custom_minimum_size = Vector2(4.0, 0.0)
	row.add_child(divider)
	_title_button = Button.new()
	NotLightL10n.bind_text(_title_button, "modules.library.board_fallback")
	NotLightL10n.bind_tooltip(_title_button, "hub.board.rename_title")
	_title_button.theme_type_variation = "GhostButton"
	_title_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_button.add_theme_font_size_override("font_size", 16)
	_title_button.pressed.connect(_open_rename_dialog)
	row.add_child(_title_button)


func _build_tool_rail() -> void:
	_tool_rail = PanelContainer.new()
	var rail: PanelContainer = _tool_rail
	rail.theme_type_variation = "FloatingPanel"
	rail.z_index = 300
	rail.set_anchors_preset(Control.PRESET_TOP_LEFT)
	rail.offset_left = 18.0
	rail.offset_right = 74.0
	rail.offset_top = 92.0
	rail.offset_bottom = 550.0
	add_child(rail)
	var tools: VBoxContainer = VBoxContainer.new()
	tools.add_theme_constant_override("separation", 4)
	rail.add_child(tools)
	var group: ButtonGroup = ButtonGroup.new()

	_hand_button = Button.new()
	_hand_button.icon = load("res://assets/icons/hand.svg") as Texture2D
	NotLightL10n.bind_tooltip(_hand_button, "runtime.ui.board_screen.267a14d6c5")
	_hand_button.theme_type_variation = "ToolButton"
	_hand_button.toggle_mode = true
	_hand_button.button_group = group
	_hand_button.custom_minimum_size = Vector2(44.0, 44.0)
	_hand_button.pressed.connect(func() -> void: _set_active_tool(BoardToolController.TOOL_HAND))
	tools.add_child(_hand_button)

	_select_button = Button.new()
	_select_button.icon = load("res://assets/icons/cursor.svg") as Texture2D
	NotLightL10n.bind_tooltip(_select_button, "runtime.ui.board_screen.0f60199287")
	_select_button.theme_type_variation = "ToolButton"
	_select_button.toggle_mode = true
	_select_button.button_group = group
	_select_button.custom_minimum_size = Vector2(44.0, 44.0)
	_select_button.pressed.connect(func() -> void: _set_active_tool(BoardToolController.TOOL_SELECT))
	tools.add_child(_select_button)

	_text_button = Button.new()
	_text_button.icon = load("res://assets/icons/text.svg") as Texture2D
	NotLightL10n.bind_tooltip(_text_button, "runtime.ui.board_screen.987b2bbd42")
	_text_button.theme_type_variation = "ToolButton"
	_text_button.toggle_mode = true
	_text_button.button_group = group
	_text_button.custom_minimum_size = Vector2(44.0, 44.0)
	_text_button.pressed.connect(func() -> void: _set_active_tool(BoardToolController.TOOL_TEXT))
	tools.add_child(_text_button)

	_draw_button = Button.new()
	_draw_button.icon = load("res://assets/icons/edit.svg") as Texture2D
	NotLightL10n.bind_tooltip(_draw_button, "board.tool.draw")
	_draw_button.theme_type_variation = "ToolButton"
	_draw_button.toggle_mode = true
	_draw_button.button_group = group
	_draw_button.custom_minimum_size = Vector2(44.0, 44.0)
	_draw_button.pressed.connect(func() -> void: _set_active_tool(BoardToolController.TOOL_DRAW))
	tools.add_child(_draw_button)

	_formula_button = Button.new()
	_formula_button.icon = load("res://assets/icons/formula.svg") as Texture2D
	NotLightL10n.bind_tooltip(_formula_button, "board.tool.formula")
	_formula_button.theme_type_variation = "ToolButton"
	_formula_button.toggle_mode = true
	_formula_button.button_group = group
	_formula_button.custom_minimum_size = Vector2(44.0, 44.0)
	_formula_button.pressed.connect(func() -> void: _set_active_tool(BoardToolController.TOOL_FORMULA))
	tools.add_child(_formula_button)

	_image_import_button = Button.new()
	_image_import_button.icon = load("res://assets/icons/image.svg") as Texture2D
	NotLightL10n.bind_tooltip(_image_import_button, "runtime.ui.board_screen.ed8d4172a4")
	_image_import_button.theme_type_variation = "IconButton"
	_image_import_button.custom_minimum_size = Vector2(44.0, 44.0)
	_image_import_button.pressed.connect(_open_image_import_dialog)
	tools.add_child(_image_import_button)

	_pdf_import_button = Button.new()
	NotLightL10n.bind_text(_pdf_import_button, "library.kind.pdf")
	NotLightL10n.bind_tooltip(_pdf_import_button, "board.tool.pdf_import")
	_pdf_import_button.theme_type_variation = "CompactRailTextButton"
	_pdf_import_button.custom_minimum_size = Vector2(44.0, 44.0)
	_pdf_import_button.pressed.connect(_open_pdf_import_dialog)
	tools.add_child(_pdf_import_button)

	_video_import_button = Button.new()
	_video_import_button.icon = load("res://assets/icons/video.svg") as Texture2D
	NotLightL10n.bind_tooltip(_video_import_button, "runtime.ui.board_screen.64c9f7c9aa")
	_video_import_button.theme_type_variation = "IconButton"
	_video_import_button.custom_minimum_size = Vector2(44.0, 44.0)
	_video_import_button.pressed.connect(_open_video_import_dialog)
	tools.add_child(_video_import_button)

	_audio_import_button = Button.new()
	_audio_import_button.icon = load("res://assets/icons/audio.svg") as Texture2D
	NotLightL10n.bind_tooltip(_audio_import_button, "board.tool.audio_import")
	_audio_import_button.theme_type_variation = "IconButton"
	_audio_import_button.custom_minimum_size = Vector2(44.0, 44.0)
	_audio_import_button.pressed.connect(_open_audio_import_dialog)
	tools.add_child(_audio_import_button)

	_voice_record_button = Button.new()
	_voice_record_button.icon = load("res://assets/icons/microphone.svg") as Texture2D
	NotLightL10n.bind_tooltip(_voice_record_button, "board.tool.voice_record")
	_voice_record_button.theme_type_variation = "IconButton"
	_voice_record_button.toggle_mode = true
	_voice_record_button.custom_minimum_size = Vector2(44.0, 44.0)
	_voice_record_button.pressed.connect(_toggle_voice_recording)
	tools.add_child(_voice_record_button)

	var separator: HSeparator = HSeparator.new()
	separator.custom_minimum_size = Vector2(0.0, 5.0)
	tools.add_child(separator)
	_library_button = Button.new()
	_library_button.icon = load("res://assets/icons/library.svg") as Texture2D
	NotLightL10n.bind_tooltip(_library_button, "board.library.tooltip")
	_library_button.theme_type_variation = "IconButton"
	_library_button.toggle_mode = true
	_library_button.custom_minimum_size = Vector2(44.0, 44.0)
	_library_button.pressed.connect(func() -> void: _set_library_drawer_open(_library_button.button_pressed))
	tools.add_child(_library_button)

	_notes_button = Button.new()
	_notes_button.text = "✎"
	NotLightL10n.bind_tooltip(_notes_button, "board.notes.tooltip")
	_notes_button.theme_type_variation = "CompactRailTextButton"
	_notes_button.custom_minimum_size = Vector2(44.0, 44.0)
	_notes_button.pressed.connect(_open_notes_browser)
	tools.add_child(_notes_button)

	_module_button = Button.new()
	_module_button.text = "◇"
	NotLightL10n.bind_tooltip(_module_button, "board.modules.tooltip")
	_module_button.theme_type_variation = "IconButton"
	_module_button.toggle_mode = true
	_module_button.custom_minimum_size = Vector2(44.0, 44.0)
	_module_button.pressed.connect(func() -> void: _set_module_picker_open(_module_button.button_pressed))
	tools.add_child(_module_button)


func _build_board_utilities() -> void:
	# Keep utility actions in their own lower-left vertical island. Stage 9.5
	# briefly anchored this panel to BOTTOM_LEFT while the responsive layout code
	# wrote absolute top coordinates, which moved the whole island off-screen.
	_utility_panel = PanelContainer.new()
	var utility_panel: PanelContainer = _utility_panel
	utility_panel.theme_type_variation = "FloatingPanel"
	utility_panel.z_index = 300
	utility_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	utility_panel.offset_left = 18.0
	utility_panel.offset_top = 366.0
	utility_panel.offset_right = 74.0
	utility_panel.offset_bottom = 568.0
	add_child(utility_panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	utility_panel.add_child(box)

	_settings_button = Button.new()
	_settings_button.icon = load("res://assets/icons/settings.svg") as Texture2D
	NotLightL10n.bind_tooltip(_settings_button, "hub.settings_tooltip")
	_settings_button.theme_type_variation = "IconButton"
	_settings_button.custom_minimum_size = Vector2(44.0, 40.0)
	_settings_button.pressed.connect(_open_settings_dialog)
	box.add_child(_settings_button)
	_configure_square_icon_button(_settings_button)

	_save_button = Button.new()
	_save_button.icon = load("res://assets/icons/save.svg") as Texture2D
	NotLightL10n.bind_tooltip(_save_button, "runtime.ui.board_screen.064106b1fa")
	_save_button.theme_type_variation = "IconButton"
	_save_button.custom_minimum_size = Vector2(44.0, 40.0)
	_save_button.pressed.connect(_save_now)
	box.add_child(_save_button)
	_configure_square_icon_button(_save_button)

	var separator: HSeparator = HSeparator.new()
	separator.custom_minimum_size = Vector2(0.0, 4.0)
	box.add_child(separator)

	_undo_button = Button.new()
	_undo_button.icon = load("res://assets/icons/undo.svg") as Texture2D
	NotLightL10n.bind_tooltip(_undo_button, "runtime.ui.board_screen.d8c1ad00a9")
	_undo_button.theme_type_variation = "IconButton"
	_undo_button.custom_minimum_size = Vector2(44.0, 40.0)
	_undo_button.pressed.connect(_on_undo_pressed)
	box.add_child(_undo_button)
	_configure_square_icon_button(_undo_button)

	_redo_button = Button.new()
	_redo_button.icon = load("res://assets/icons/redo.svg") as Texture2D
	NotLightL10n.bind_tooltip(_redo_button, "runtime.ui.board_screen.abf4340421")
	_redo_button.theme_type_variation = "IconButton"
	_redo_button.custom_minimum_size = Vector2(44.0, 40.0)
	_redo_button.pressed.connect(_on_redo_pressed)
	box.add_child(_redo_button)
	_configure_square_icon_button(_redo_button)


func _build_asset_library_drawer() -> void:
	_library_drawer = PanelContainer.new()
	_library_drawer.name = "AssetLibraryDrawer"
	_library_drawer.theme_type_variation = "LibraryDrawerPanel"
	_library_drawer.clip_contents = false
	_library_drawer.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_library_drawer.offset_left = -448.0
	_library_drawer.offset_top = 22.0
	_library_drawer.offset_right = -22.0
	_library_drawer.offset_bottom = -94.0
	_library_drawer.visible = false
	_library_drawer.z_index = 500
	add_child(_library_drawer)
	_asset_view = AssetLibraryView.new()
	_asset_view.set_compact_mode(true)
	_asset_view.request_close.connect(func() -> void: _set_library_drawer_open(false))
	_asset_view.error_requested.connect(_show_error)
	_asset_view.asset_insert_requested.connect(_place_library_asset)
	_asset_view.note_workspace_insert_requested.connect(_place_library_note_workspace)
	_asset_view.asset_preview_requested.connect(_open_asset_preview)
	_asset_view.notes_graph_requested.connect(_open_notes_graph)
	_library_drawer.add_child(_asset_view)


func _set_library_drawer_open(should_open: bool) -> void:
	if should_open and _module_picker_open:
		_set_module_picker_open(false)
	if should_open and _formula_editor != null and _formula_editor.visible:
		if _library_button != null:
			_library_button.set_pressed_no_signal(false)
		return
	_library_drawer_open = should_open
	if _library_button != null:
		_library_button.set_pressed_no_signal(should_open)
	if _library_drawer == null:
		return
	if _library_drawer_tween != null:
		_library_drawer_tween.kill()
	_library_drawer_tween = create_tween()
	_library_drawer_tween.set_parallel(true)
	_library_drawer_tween.set_trans(Tween.TRANS_CUBIC)
	_library_drawer_tween.set_ease(Tween.EASE_OUT)
	if should_open:
		_library_drawer.visible = true
		_library_drawer.offset_left = 16.0
		_library_drawer.offset_right = 448.0
		_library_drawer.modulate.a = 0.72
		_library_drawer_tween.tween_property(_library_drawer, "offset_left", -448.0, 0.22)
		_library_drawer_tween.tween_property(_library_drawer, "offset_right", -22.0, 0.22)
		_library_drawer_tween.tween_property(_library_drawer, "modulate:a", 1.0, 0.16)
		if _asset_view != null:
			_asset_view.call_deferred("focus_search")
	else:
		_library_drawer_tween.tween_property(_library_drawer, "offset_left", 16.0, 0.18)
		_library_drawer_tween.tween_property(_library_drawer, "offset_right", 448.0, 0.18)
		_library_drawer_tween.tween_property(_library_drawer, "modulate:a", 0.72, 0.14)
		_library_drawer_tween.finished.connect(_finish_library_drawer_close)


func _finish_library_drawer_close() -> void:
	if _library_drawer != null and not _library_drawer_open:
		_library_drawer.visible = false
		_library_drawer.offset_left = -448.0
		_library_drawer.offset_right = -22.0
		_library_drawer.modulate.a = 1.0


func _build_module_surface_pool() -> void:
	_module_surface_pool = ModuleSurfacePool.new()
	_module_surface_pool.name = "ModuleSurfacePool"
	_module_surface_pool.z_as_relative = true
	_module_surface_pool.z_index = 180
	_module_surface_pool.surface_error.connect(_show_error)
	# Keep live ModuleObject Controls in NativeBoardView's own local coordinate space.
	# This removes the sibling-overlay transform boundary that could leave a live
	# surface visually attached to the screen until the next pointer event.
	_board_view.add_child(_module_surface_pool)


func _build_note_surface_pool() -> void:
	_note_surface_pool = NoteBoardSurfacePool.new()
	_note_surface_pool.name = "NoteBoardSurfacePool"
	_note_surface_pool.z_as_relative = true
	_note_surface_pool.z_index = 190
	_note_surface_pool.surface_error.connect(_show_error)
	_note_surface_pool.asset_preview_requested.connect(_open_asset_preview)
	_board_view.add_child(_note_surface_pool)


func _build_module_picker() -> void:
	_module_picker = ModulePickerPanel.new()
	_module_picker.name = "ModulePickerPanel"
	_module_picker.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_module_picker.offset_left = -448.0
	_module_picker.offset_top = 22.0
	_module_picker.offset_right = -22.0
	_module_picker.offset_bottom = -94.0
	_module_picker.z_index = 500
	_module_picker.visible = false
	_module_picker.module_create_requested.connect(_create_module_object)
	_module_picker.close_requested.connect(func() -> void: _set_module_picker_open(false))
	add_child(_module_picker)


func _set_module_picker_open(should_open: bool) -> void:
	if should_open and (_formula_editor != null and _formula_editor.visible):
		if _module_button != null:
			_module_button.set_pressed_no_signal(false)
		return
	if should_open and _library_drawer_open:
		_set_library_drawer_open(false)
	_module_picker_open = should_open
	if _module_button != null:
		_module_button.set_pressed_no_signal(should_open)
	if _module_picker == null:
		return
	if _module_picker_tween != null:
		_module_picker_tween.kill()
	_module_picker_tween = create_tween()
	_module_picker_tween.set_parallel(true)
	_module_picker_tween.set_trans(Tween.TRANS_CUBIC)
	_module_picker_tween.set_ease(Tween.EASE_OUT)
	if should_open:
		_module_picker.visible = true
		_module_picker.offset_left = 16.0
		_module_picker.offset_right = 448.0
		_module_picker.modulate.a = 0.72
		_module_picker.move_to_front()
		_module_picker_tween.tween_property(_module_picker, "offset_left", -448.0, 0.22)
		_module_picker_tween.tween_property(_module_picker, "offset_right", -22.0, 0.22)
		_module_picker_tween.tween_property(_module_picker, "modulate:a", 1.0, 0.16)
		_module_picker.call_deferred("focus_search")
	else:
		_module_picker_tween.tween_property(_module_picker, "offset_left", 16.0, 0.18)
		_module_picker_tween.tween_property(_module_picker, "offset_right", 448.0, 0.18)
		_module_picker_tween.tween_property(_module_picker, "modulate:a", 0.72, 0.14)
		_module_picker_tween.finished.connect(_finish_module_picker_close)


func _finish_module_picker_close() -> void:
	if _module_picker != null and not _module_picker_open:
		_module_picker.visible = false
		_module_picker.offset_left = -448.0
		_module_picker.offset_right = -22.0
		_module_picker.modulate.a = 1.0


func _create_module_object(module_id: String) -> void:
	if session == null or module_registry == null:
		return
	var clean_id: String = module_id.strip_edges().to_lower()
	if not module_registry.is_module_active(clean_id):
		_show_error(NotLightL10n.text("modules.board.not_active", {"id": clean_id}))
		return
	var state: Dictionary = module_registry.default_state(clean_id)
	if state.is_empty():
		_show_error(NotLightL10n.text("modules.board.default_state_failed"))
		return
	var manifest: Dictionary = module_registry.get_active_manifest(clean_id)
	var title: String = str(manifest.get("name", clean_id))
	var center: Vector2 = _board_view.get_view_center_world_position()
	var default_size: Vector2 = Vector2(760.0, 480.0)
	var bounds: Rect2 = Rect2(center - default_size * 0.5, default_size)
	var command: CreateModuleCommand = CreateModuleCommand.new(
		bounds,
		clean_id,
		module_registry.get_state_schema_version(clean_id),
		state,
		title,
		PackedStringArray(),
		session.runtime.model.get_max_z_order() + 1
	)
	if not session.execute_command(command):
		_show_error(NotLightL10n.text("modules.board.create_failed"))
		return
	_set_module_picker_open(false)
	if command.created_entity_id > 0:
		session.runtime.selection.set_single(command.created_entity_id)
		if _module_surface_pool != null:
			_module_surface_pool.activate(command.created_entity_id)
	_mark_board_search_snapshot_dirty()


func _on_module_open_requested(entity_id: int) -> void:
	if _module_surface_pool == null:
		return
	if not _module_surface_pool.activate(entity_id):
		var module_id: String = session.runtime.model.modules.get_module_id(entity_id) if session != null and session.runtime.model.modules.contains(entity_id) else ""
		if module_registry == null or not module_registry.is_module_active(module_id):
			_show_error(NotLightL10n.text("modules.board.missing", {"id": module_id}))


func _build_board_search_panel() -> void:
	_board_search_panel = BoardSearchPanel.new()
	_board_search_panel.name = "BoardSearchPanel"
	_board_search_panel.entity_requested.connect(_focus_board_search_entity)
	_board_search_panel.open_changed.connect(_on_board_search_open_changed)
	add_child(_board_search_panel)


func _toggle_board_search() -> void:
	if _board_search_panel == null:
		return
	# Keep the shortcut symmetric: the same Ctrl/Command+F that opens search closes
	# it again, including while the query field owns keyboard focus.
	if _board_search_panel.is_open():
		_board_search_panel.close_panel()
		return
	_board_view.commit_active_editor()
	_refresh_board_search_snapshot(true)
	_board_search_panel.open_panel()


func _on_board_search_open_changed(is_open: bool) -> void:
	if is_open:
		_refresh_board_search_snapshot(false)


func _focus_board_search_entity(entity_id: int) -> void:
	if _board_view == null or entity_id <= 0:
		return
	if not _board_view.focus_entity(entity_id, true):
		_mark_board_search_snapshot_dirty()
		_refresh_board_search_snapshot(true)


func _mark_board_search_snapshot_dirty() -> void:
	_board_search_snapshot_dirty = true


func _refresh_board_search_snapshot(force: bool = false) -> void:
	if _board_search_panel == null or session == null:
		return
	var signature: String = _current_board_search_signature()
	if not force and not _board_search_snapshot_dirty and signature == _board_search_snapshot_signature:
		return
	_board_search_panel.set_snapshot(BoardSearchSnapshot.build(session.runtime.model, asset_library, note_repository))
	_board_search_snapshot_signature = signature
	_board_search_snapshot_dirty = false


func _current_board_search_signature() -> String:
	if session == null:
		return ""
	var model: BoardModel = session.runtime.model
	return "%d:%d:%d:%d:%d:%d:%d" % [model.text_revision, model.formula_revision, model.image_revision, model.pdf_revision, model.video_revision, model.audio_revision, model.note_portal_revision]


func _build_text_context_toolbar() -> void:
	_text_toolbar = TextContextToolbar.new()
	_text_toolbar.edit_requested.connect(func() -> void: _board_view.edit_primary_text(false))
	_text_toolbar.delete_requested.connect(_board_view.delete_selection)
	_text_toolbar.font_family_requested.connect(_set_selected_font_family)
	_text_toolbar.font_size_requested.connect(_set_selected_font_size)
	_text_toolbar.font_style_requested.connect(_change_selected_font_style)
	_text_toolbar.alignment_requested.connect(_change_selected_alignment)
	_text_toolbar.list_type_requested.connect(_change_selected_list_type)
	_text_toolbar.list_indent_requested.connect(_change_selected_list_indent)
	_text_toolbar.text_color_requested.connect(_change_selected_text_color)
	_text_toolbar.background_color_requested.connect(_change_selected_background_color)
	_text_toolbar.background_opacity_requested.connect(_change_selected_background_opacity)
	_text_toolbar.text_color_picker_requested.connect(_open_text_color_popover)
	_text_toolbar.background_color_picker_requested.connect(_open_background_color_popover)
	add_child(_text_toolbar)


func _build_connector_context_toolbar() -> void:
	_connector_toolbar = ConnectorContextToolbar.new()
	_connector_toolbar.direction_requested.connect(_change_selected_connector_direction)
	_connector_toolbar.color_picker_requested.connect(_open_connector_color_popover)
	_connector_toolbar.delete_requested.connect(_board_view.delete_selection)
	add_child(_connector_toolbar)


func _build_image_context_toolbar() -> void:
	_image_toolbar = ImageContextToolbar.new()
	_image_toolbar.rename_requested.connect(_open_selected_image_rename_dialog)
	_image_toolbar.duplicate_requested.connect(_board_view.duplicate_selection)
	_image_toolbar.delete_requested.connect(_board_view.delete_selection)
	add_child(_image_toolbar)


func _build_pdf_context_toolbar() -> void:
	_pdf_toolbar = PdfContextToolbar.new()
	_pdf_toolbar.previous_page_requested.connect(_show_previous_pdf_page)
	_pdf_toolbar.next_page_requested.connect(_show_next_pdf_page)
	_pdf_toolbar.page_requested.connect(_show_pdf_page)
	_pdf_toolbar.rename_requested.connect(_open_selected_pdf_rename_dialog)
	_pdf_toolbar.duplicate_requested.connect(_board_view.duplicate_selection)
	_pdf_toolbar.delete_requested.connect(_board_view.delete_selection)
	add_child(_pdf_toolbar)


func _build_video_context_toolbar() -> void:
	_video_toolbar = VideoContextToolbar.new()
	_video_toolbar.rename_requested.connect(_open_selected_video_rename_dialog)
	_video_toolbar.duplicate_requested.connect(_board_view.duplicate_selection)
	_video_toolbar.optimize_requested.connect(_optimize_selected_video)
	_video_toolbar.delete_requested.connect(_board_view.delete_selection)
	add_child(_video_toolbar)


func _build_audio_context_toolbar() -> void:
	_audio_toolbar = AudioContextToolbar.new()
	_audio_toolbar.play_requested.connect(_play_selected_audio)
	_audio_toolbar.rename_requested.connect(_open_selected_audio_rename_dialog)
	_audio_toolbar.duplicate_requested.connect(_board_view.duplicate_selection)
	_audio_toolbar.delete_requested.connect(_board_view.delete_selection)
	add_child(_audio_toolbar)



func _build_stroke_context_toolbar() -> void:
	_stroke_toolbar = StrokeContextToolbar.new()
	_stroke_toolbar.width_requested.connect(_change_selected_stroke_width)
	_stroke_toolbar.spray_spread_requested.connect(_change_selected_stroke_spread)
	_stroke_toolbar.color_picker_requested.connect(_open_stroke_color_popover)
	_stroke_toolbar.duplicate_requested.connect(_board_view.duplicate_selection)
	_stroke_toolbar.delete_requested.connect(_board_view.delete_selection)
	add_child(_stroke_toolbar)


func _build_formula_context_toolbar() -> void:
	_formula_toolbar = FormulaContextToolbar.new()
	_formula_toolbar.edit_requested.connect(func() -> void:
		var entity_id: int = _selected_formula_id()
		if entity_id > 0:
			_on_formula_edit_requested(entity_id)
	)
	_formula_toolbar.copy_latex_requested.connect(_copy_selected_formula_latex)
	_formula_toolbar.display_mode_requested.connect(_change_selected_formula_mode)
	_formula_toolbar.color_picker_requested.connect(_open_formula_object_color_popover)
	_formula_toolbar.duplicate_requested.connect(_board_view.duplicate_selection)
	_formula_toolbar.delete_requested.connect(_board_view.delete_selection)
	add_child(_formula_toolbar)


func _build_drawing_palette() -> void:
	_drawing_palette = DrawingToolPalette.new()
	_drawing_palette.brush_changed.connect(_on_drawing_brush_changed)
	_drawing_palette.color_picker_requested.connect(_open_drawing_color_popover)
	add_child(_drawing_palette)

func _build_color_popover() -> void:
	_color_popover = BoardColorPopover.new()
	_color_popover.color_committed.connect(_on_color_popover_committed)
	_color_popover.canceled.connect(_on_color_popover_canceled)
	add_child(_color_popover)


func _build_status_controls() -> void:
	# Zoom controls own the bottom-right corner. Performance metrics live in a
	# separate panel that expands to the left, so enabling RAM/CPU/VRAM can never
	# push the zoom widget beyond the viewport.
	_status_panel = PanelContainer.new()
	_status_panel.theme_type_variation = "FloatingPanel"
	_status_panel.z_index = 300
	add_child(_status_panel)
	var zoom_row: HBoxContainer = HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 3)
	_status_panel.add_child(zoom_row)

	var minus_button: Button = Button.new()
	minus_button.text = "−"
	NotLightL10n.bind_tooltip(minus_button, "runtime.ui.board_screen.bf9ec49032")
	minus_button.theme_type_variation = "GhostButton"
	minus_button.custom_minimum_size = Vector2(38.0, 38.0)
	minus_button.pressed.connect(_board_view.zoom_out)
	zoom_row.add_child(minus_button)

	_zoom_label = Label.new()
	_zoom_label.text = NotLightL10n.text("ui.format.percent_int") % 100
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zoom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_zoom_label.custom_minimum_size = Vector2(58.0, 38.0)
	_zoom_label.theme_type_variation = "CaptionStrongLabel"
	zoom_row.add_child(_zoom_label)

	var plus_button: Button = Button.new()
	plus_button.text = "+"
	NotLightL10n.bind_tooltip(plus_button, "runtime.ui.board_screen.b618f471ee")
	plus_button.theme_type_variation = "GhostButton"
	plus_button.custom_minimum_size = Vector2(38.0, 38.0)
	plus_button.pressed.connect(_board_view.zoom_in)
	zoom_row.add_child(plus_button)

	_zoom_reset_button = Button.new()
	NotLightL10n.bind_text(_zoom_reset_button, "runtime.ui.board_screen.9322bf379d")
	NotLightL10n.bind_tooltip(_zoom_reset_button, "runtime.ui.board_screen.e4f42a165b")
	_zoom_reset_button.theme_type_variation = "GhostButton"
	_zoom_reset_button.custom_minimum_size = Vector2(66.0, 38.0)
	_zoom_reset_button.pressed.connect(_board_view.reset_view)
	zoom_row.add_child(_zoom_reset_button)

	_monitor_panel = PanelContainer.new()
	_monitor_panel.theme_type_variation = "FloatingPanel"
	_monitor_panel.z_index = 300
	add_child(_monitor_panel)
	_monitor_strip = PerformanceMonitorStrip.new()
	_monitor_strip.visibility_layout_changed.connect(_update_bottom_layout)
	_monitor_panel.add_child(_monitor_strip)

	_developer_panel_container = PanelContainer.new()
	_developer_panel_container.theme_type_variation = "FloatingPanel"
	_developer_panel_container.z_index = 300
	_developer_panel_container.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_developer_panel_container)
	_developer_panel = DeveloperDiagnosticsPanel.new()
	_developer_panel.visibility_layout_changed.connect(_update_bottom_layout)
	_developer_panel_container.add_child(_developer_panel)

func _build_hint() -> void:
	_hint_panel = PanelContainer.new()
	var hint: PanelContainer = _hint_panel
	hint.theme_type_variation = "SoftPanel"
	hint.z_index = 300
	hint.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The label owns its own two-line clipping. Avoid clipping the whole panel's
	# child layout while Godot recalculates autowrap height on resize.
	hint.clip_contents = false
	add_child(hint)
	_hint_label = Label.new()
	NotLightL10n.bind_text(_hint_label, "board.hint.select")
	_hint_label.theme_type_variation = "CaptionLabel"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.max_lines_visible = 2
	_hint_label.clip_text = true
	_hint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hint_label.add_theme_color_override("font_color", NotLightTheme.semantic_color("text"))
	hint.add_child(_hint_label)


func _build_welcome_panel() -> void:
	_welcome_panel = PanelContainer.new()
	_welcome_panel.theme_type_variation = "CardPanel"
	_welcome_panel.z_index = 250
	_welcome_panel.set_anchors_preset(Control.PRESET_CENTER)
	_welcome_panel.position = Vector2(-260.0, -126.0)
	_welcome_panel.size = Vector2(520.0, 252.0)
	_welcome_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_welcome_panel)

	var center: CenterContainer = CenterContainer.new()
	_welcome_panel.add_child(center)
	var content: VBoxContainer = VBoxContainer.new()
	content.custom_minimum_size = Vector2(440.0, 0.0)
	content.add_theme_constant_override("separation", 12)
	center.add_child(content)
	var icon: Label = Label.new()
	icon.text = "∞"
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 48)
	icon.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
	content.add_child(icon)
	var title: Label = Label.new()
	NotLightL10n.bind_text(title, "runtime.ui.board_screen.f9d8280230")
	title.theme_type_variation = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var description: Label = Label.new()
	NotLightL10n.bind_text(description, "runtime.ui.board_screen.d4bfd629b1")
	description.theme_type_variation = "BodyMutedLabel"
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(description)
	var hint: Label = Label.new()
	NotLightL10n.bind_text(hint, "runtime.ui.board_screen.9ceb6ce3f2")
	hint.theme_type_variation = "CaptionLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(hint)


func _build_rename_dialog() -> void:
	_rename_dialog = NameDialog.new()
	_rename_dialog.submitted.connect(_rename_current_board)
	add_child(_rename_dialog)


func _build_asset_rename_dialog() -> void:
	_asset_rename_dialog = NameDialog.new()
	_asset_rename_dialog.submitted.connect(_rename_selected_asset)
	add_child(_asset_rename_dialog)


func _build_image_import_dialog() -> void:
	_image_import_dialog = FileDialog.new()
	_image_import_dialog.mode_overrides_title = false
	_image_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_image_import_dialog.title = NotLightL10n.text("board.import.image_title")
	_image_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_image_import_dialog.use_native_dialog = true
	_image_import_dialog.filters = AssetImportCapabilities.file_dialog_filters(AssetKinds.IMAGE)
	_image_import_dialog.files_selected.connect(_on_image_files_selected)
	add_child(_image_import_dialog)


func _build_pdf_import_dialog() -> void:
	_pdf_import_dialog = FileDialog.new()
	_pdf_import_dialog.mode_overrides_title = false
	_pdf_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_pdf_import_dialog.title = NotLightL10n.text("board.import.pdf_title")
	_pdf_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_pdf_import_dialog.use_native_dialog = true
	_pdf_import_dialog.filters = AssetImportCapabilities.file_dialog_filters(AssetKinds.PDF)
	_pdf_import_dialog.files_selected.connect(_on_pdf_files_selected)
	add_child(_pdf_import_dialog)


func _build_video_import_dialog() -> void:
	_video_import_dialog = FileDialog.new()
	_video_import_dialog.mode_overrides_title = false
	_video_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_video_import_dialog.title = NotLightL10n.text("board.import.video_title")
	_video_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_video_import_dialog.use_native_dialog = true
	_video_import_dialog.filters = AssetImportCapabilities.file_dialog_filters(AssetKinds.VIDEO)
	_video_import_dialog.files_selected.connect(_on_video_files_selected)
	add_child(_video_import_dialog)


func _build_audio_import_dialog() -> void:
	_audio_import_dialog = FileDialog.new()
	_audio_import_dialog.mode_overrides_title = false
	_audio_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_audio_import_dialog.title = NotLightL10n.text("board.import.audio_title")
	_audio_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_audio_import_dialog.use_native_dialog = true
	_audio_import_dialog.filters = AssetImportCapabilities.file_dialog_filters(AssetKinds.AUDIO)
	_audio_import_dialog.files_selected.connect(_on_audio_files_selected)
	add_child(_audio_import_dialog)


func _build_settings_dialog() -> void:
	_settings_dialog = SettingsDialog.new()
	_settings_dialog.visible = false
	add_child(_settings_dialog)


func _build_microphone_permission_dialog() -> void:
	_microphone_permission_dialog = MicrophonePermissionDialog.new()
	_microphone_permission_dialog.allow_requested.connect(_on_microphone_permission_allowed)
	_microphone_permission_dialog.decline_requested.connect(_on_microphone_permission_declined)
	_microphone_permission_dialog.system_settings_requested.connect(_open_system_microphone_settings)
	add_child(_microphone_permission_dialog)


func _build_error_message() -> void:
	_error_panel = PanelContainer.new()
	_error_panel.theme_type_variation = "FloatingPanel"
	_error_panel.z_index = 900
	_error_panel.visible = false
	_error_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_error_panel.offset_left = -260.0
	_error_panel.offset_top = 160.0
	_error_panel.offset_right = 260.0
	_error_panel.offset_bottom = 216.0
	add_child(_error_panel)
	_error_label = Label.new()
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.add_theme_color_override("font_color", NotLightTheme.semantic_color("danger"))
	_error_panel.add_child(_error_label)
	_error_timer = Timer.new()
	_error_timer.one_shot = true
	_error_timer.wait_time = 4.0
	_error_timer.timeout.connect(func() -> void: _error_panel.visible = false)
	add_child(_error_timer)




func flush_view_state() -> void:
	if _board_view == null or session == null:
		return
	_board_view.commit_active_editor()
	_board_view.flush_view_state()
	session.update_view_state(_board_view.get_view_state())


func _request_back() -> void:
	_discard_formula_draft()
	flush_view_state()
	back_requested.emit()


func _save_now() -> void:
	_discard_formula_draft()
	if session == null:
		return
	flush_view_state()
	session.request_save()


func _set_active_tool(tool_id: StringName) -> void:
	if session != null:
		session.runtime.tools.set_active_tool(tool_id)


func _on_view_state_changed(view_state: Dictionary) -> void:
	if session != null:
		session.update_view_state(view_state)


func _on_zoom_changed(value: float) -> void:
	if _zoom_label != null:
		_zoom_label.text = NotLightL10n.text("ui.format.percent_int") % int(round(value * 100.0))


func _on_metadata_changed(new_metadata: Dictionary) -> void:
	_board_display_name = str(new_metadata.get("name", NotLightL10n.text("notes.untitled")))
	_update_title_save_marker()


func _on_save_state_changed(state: BoardSession.SaveState, message: String) -> void:
	_save_state = state
	_update_title_save_marker()
	if _save_button != null:
		_save_button.tooltip_text = NotLightL10n.text("ui.format.save_shortcut") % message
	if state == BoardSession.SaveState.ERROR:
		_show_error(message)


func _update_title_save_marker() -> void:
	if _title_button == null:
		return
	var has_unsaved_changes: bool = _save_state != BoardSession.SaveState.SAVED
	_title_button.text = NotLightL10n.text("ui.format.unsaved_title") % _board_display_name if has_unsaved_changes else _board_display_name
	_title_button.tooltip_text = NotLightL10n.text("ui.format.two_parts") % [
		NotLightL10n.text("hub.board.rename_title"),
		NotLightL10n.text("runtime.ui.board_screen.e794f7ddab") if has_unsaved_changes else NotLightL10n.text("runtime.ui.board_screen.34ec4378c7"),
	]


func _on_history_changed(can_undo: bool, can_redo: bool, undo_label: String, redo_label: String) -> void:
	if _undo_button != null:
		_undo_button.disabled = not can_undo
		_undo_button.tooltip_text = NotLightL10n.text("runtime.ui.board_screen.1fa1d2b45b") % undo_label if can_undo else NotLightL10n.text("runtime.ui.board_screen.2d3cb29c27")
	if _redo_button != null:
		_redo_button.disabled = not can_redo
		_redo_button.tooltip_text = NotLightL10n.text("runtime.ui.board_screen.1c636be91e") % redo_label if can_redo else NotLightL10n.text("runtime.ui.board_screen.b3e166622f")


func _on_active_tool_changed(tool_id: StringName) -> void:
	if _hand_button != null:
		_hand_button.button_pressed = tool_id == BoardToolController.TOOL_HAND
	if _select_button != null:
		_select_button.button_pressed = tool_id == BoardToolController.TOOL_SELECT
	if _text_button != null:
		_text_button.button_pressed = tool_id == BoardToolController.TOOL_TEXT
	if _draw_button != null:
		_draw_button.button_pressed = tool_id == BoardToolController.TOOL_DRAW
	if _formula_button != null:
		_formula_button.button_pressed = tool_id == BoardToolController.TOOL_FORMULA
	_board_view.set_active_tool(tool_id)
	if _drawing_palette != null and _tool_rail != null:
		_drawing_palette.set_tool_active(tool_id == BoardToolController.TOOL_DRAW, size, _tool_rail.get_global_rect())
	_refresh_context_toolbars()
	_update_hint_text()


func _active_video_budget() -> int:
	if settings == null:
		return 10
	return clampi(int(settings.get_performance_budget().get("active_video_players", 10)), 1, AppSettingsStore.MAX_VIDEO_PLAYERS)


func _active_audio_budget() -> int:
	# Audio players are much lighter than video players, but bounded materialization
	# keeps a dense board predictable even when many cards were started manually.
	if settings == null:
		return AudioPlayerPool.DEFAULT_MAX_ACTIVE_PLAYERS
	var video_budget: int = int(settings.get_performance_budget().get("active_video_players", 10))
	return clampi(maxi(6, video_budget * 2), 6, 24)


func _active_module_budget() -> int:
	if settings == null:
		return ModuleSurfacePool.DEFAULT_MAX_ACTIVE_SURFACES
	return clampi(
		int(settings.get_performance_budget().get("active_module_surfaces", ModuleSurfacePool.DEFAULT_MAX_ACTIVE_SURFACES)),
		AppSettingsStore.MIN_MODULE_SURFACES,
		AppSettingsStore.MAX_MODULE_SURFACES
	)


func _active_note_workspace_budget() -> int:
	if settings == null:
		return NoteBoardSurfacePool.DEFAULT_MAX_ACTIVE_SURFACES
	return clampi(
		int(
			settings.get_performance_budget().get(
				"active_note_workspace_surfaces",
				NoteBoardSurfacePool.DEFAULT_MAX_ACTIVE_SURFACES
			)
		),
		AppSettingsStore.MIN_NOTE_WORKSPACE_SURFACES,
		AppSettingsStore.MAX_NOTE_WORKSPACE_SURFACES
	)


func _on_board_interaction_activity() -> void:
	# Keep this connection bound to BoardScreen rather than a particular session
	# instance. configure() can be called again during application lifetime, and a
	# stale callable would otherwise keep resetting the previous session's clock.
	if session != null:
		session.notify_user_activity()


func _on_settings_changed(snapshot: Dictionary) -> void:
	_board_view.apply_settings(snapshot)
	_board_view.refresh_palette()
	if _video_player_pool != null:
		_video_player_pool.set_active_player_budget(_active_video_budget())
	if _module_surface_pool != null:
		_module_surface_pool.set_active_surface_budget(_active_module_budget())
		_module_surface_pool.push_theme_changed()
	if _note_surface_pool != null:
		_note_surface_pool.set_active_surface_budget(_active_note_workspace_budget())
		_note_surface_pool.push_theme_changed()
	_update_bottom_layout()
	# Live video/module/rich-Notes budgets are safe to adjust while a board is open.
	# Lowering a pool deterministically releases presentation instances only; canonical
	# board/module/note state remains host-owned. Raising a pool allocates nothing until
	# the user activates another player/surface.
	_update_hint_text()


func _update_bottom_layout() -> void:
	if _hint_panel == null:
		return
	_layout_left_controls()
	_layout_status_controls()
	if _drawing_palette != null and _tool_rail != null and _drawing_palette.visible:
		_drawing_palette.update_layout(size, _tool_rail.get_global_rect())
	# Re-evaluate the selected entity kind on resize. Passing the generic
	# context flag to every toolbar can briefly reveal a stale image/video
	# toolbar when another entity type is selected.
	_refresh_context_toolbars()
	if _color_popover != null:
		_color_popover.update_viewport(size)
	_layout_tool_hint()


func _layout_tool_hint() -> void:
	if _hint_panel == null or _hint_label == null:
		return
	var enabled: bool = true
	if settings != null:
		enabled = bool(settings.get_snapshot().get("show_tool_hints", true))
	var editor_open: bool = _formula_editor != null and _formula_editor.visible
	if not enabled or editor_open or _utility_panel == null or _status_panel == null:
		_hint_panel.visible = false
		return

	const MARGIN: float = 18.0
	const GAP: float = 10.0
	const MIN_WIDTH: float = 260.0
	const MAX_WIDTH: float = 720.0
	const HEIGHT: float = 64.0
	var left: float = _utility_panel.position.x + _utility_panel.size.x + GAP
	var right_limit: float = _status_panel.position.x - GAP
	if _monitor_panel != null and _monitor_panel.visible:
		right_limit = minf(right_limit, _monitor_panel.position.x - GAP)
	var available: float = right_limit - left
	var top: float = maxf(MARGIN, size.y - MARGIN - HEIGHT)

	# Prefer the empty strip immediately to the right of Settings/Save/Undo/Redo.
	# On compact windows, move above that island rather than covering zoom/metrics.
	if available < MIN_WIDTH:
		left = MARGIN
		right_limit = maxf(left + MIN_WIDTH, _status_panel.position.x - GAP)
		if _monitor_panel != null and _monitor_panel.visible:
			right_limit = minf(right_limit, _monitor_panel.position.x - GAP)
		available = right_limit - left
		top = maxf(90.0, _utility_panel.position.y - GAP - HEIGHT)
	if available < 180.0:
		_hint_panel.visible = false
		return

	var width: float = minf(MAX_WIDTH, available)
	_hint_panel.visible = true
	_hint_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hint_panel.position = Vector2(left, top)
	_hint_panel.size = Vector2(width, HEIGHT)


func _configure_square_icon_button(button: Button) -> void:
	button.custom_minimum_size = Vector2(44.0, 44.0)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 20)


func _layout_left_controls() -> void:
	if _tool_rail == null or _utility_panel == null:
		return
	const TOP_SAFE: float = 86.0
	const BOTTOM_MARGIN: float = 18.0
	const SAFE_GAP: float = 14.0
	var rail_height: float = maxf(220.0, _tool_rail.get_combined_minimum_size().y)
	var utility_height: float = maxf(184.0, _utility_panel.get_combined_minimum_size().y)
	var utility_top: float = maxf(TOP_SAFE + rail_height + SAFE_GAP, size.y - BOTTOM_MARGIN - utility_height)
	var workspace_bottom: float = utility_top - SAFE_GAP
	var centered_top: float = TOP_SAFE + maxf(0.0, (workspace_bottom - TOP_SAFE - rail_height) * 0.5)
	var rail_top: float = clampf(centered_top, TOP_SAFE, maxf(TOP_SAFE, workspace_bottom - rail_height))
	_tool_rail.offset_top = rail_top
	_tool_rail.offset_bottom = rail_top + rail_height
	_utility_panel.offset_top = utility_top
	_utility_panel.offset_bottom = minf(size.y - BOTTOM_MARGIN, utility_top + utility_height)


func _on_undo_pressed() -> void:
	_discard_formula_draft()
	_board_view.commit_active_editor()
	if session != null:
		session.undo()


func _on_redo_pressed() -> void:
	_discard_formula_draft()
	_board_view.commit_active_editor()
	if session != null:
		session.redo()


func _hide_welcome() -> void:
	if _welcome_panel == null or not _welcome_panel.visible:
		return
	var tween: Tween = create_tween()
	tween.tween_property(_welcome_panel, "modulate:a", 0.0, 0.18)
	tween.tween_callback(func() -> void: _welcome_panel.visible = false)


func _on_context_anchor_changed(screen_rect: Rect2, should_show: bool) -> void:
	var was_requested: bool = _text_toolbar_should_show
	_text_toolbar_anchor = screen_rect
	_text_toolbar_should_show = should_show
	# A camera interaction intentionally hides the contextual HUD. On the single
	# false -> true restore edge, rebuild the lightweight toolbar context once so
	# a stale internal visibility flag can never leave the selection HUD hidden.
	# Ordinary camera anchor movement remains reposition-only and does no asset IO.
	if should_show and not was_requested:
		_refresh_context_toolbars()
	else:
		_reposition_context_toolbars()


func _on_selection_context_changed(_selected_ids: PackedInt64Array, _primary_id: int) -> void:
	_close_color_popover()
	_refresh_context_toolbars()
	_update_hint_text()


func _on_runtime_context_changed() -> void:
	_refresh_context_toolbars()
	_mark_board_search_snapshot_dirty()


func _on_text_editor_state_changed(entity_id: int) -> void:
	_editing_text_entity_id = entity_id
	_refresh_context_toolbars()


func _on_text_editor_format_changed() -> void:
	_refresh_context_toolbars()


func _refresh_text_toolbar() -> void:
	_refresh_context_toolbars()


func _refresh_context_toolbars() -> void:
	if session == null:
		return
	if telemetry != null:
		telemetry.record_developer_counter(&"context_refreshes")
	var selected_ids: PackedInt64Array = session.runtime.selection.get_selected_ids()
	var context_ids: PackedInt64Array = selected_ids if not _selection_has_mixed_entity_types() else PackedInt64Array()
	if _text_toolbar != null:
		var editor_context: Dictionary = _board_view.get_editor_format_context() if _editing_text_entity_id > 0 else {}
		_text_toolbar.update_context(
			session.runtime,
			context_ids,
			_editing_text_entity_id,
			editor_context
		)
	if _connector_toolbar != null:
		_connector_toolbar.update_context(session.runtime, context_ids)
	if _image_toolbar != null:
		var image_id: int = _selected_image_id()
		if image_id > 0 and asset_library != null:
			var asset_id: String = session.runtime.model.images.get_asset_id(image_id)
			var asset: Dictionary = asset_library.get_asset(asset_id)
			var source_path: String = asset_library.resolve_asset_path(asset_id)
			var image_source_available: bool = (
				not asset.is_empty()
				and not source_path.is_empty()
				and FileAccess.file_exists(source_path)
			)
			var image_instance_title: String = session.runtime.model.images.get_instance_title(image_id)
			var image_display_name: String = image_instance_title if not image_instance_title.is_empty() else str(asset.get("display_name", NotLightL10n.text("board.asset.image")))
			_image_toolbar.configure(image_display_name, image_source_available)
	if _pdf_toolbar != null:
		var pdf_id: int = _selected_pdf_id()
		if pdf_id > 0 and asset_library != null:
			var pdf_asset_id: String = session.runtime.model.pdfs.get_asset_id(pdf_id)
			var pdf_asset: Dictionary = asset_library.get_asset(pdf_asset_id)
			var pdf_source_path: String = asset_library.resolve_asset_path(pdf_asset_id)
			var pdf_source_available: bool = not pdf_asset.is_empty() and not pdf_source_path.is_empty() and FileAccess.file_exists(pdf_source_path)
			var pdf_instance_title: String = session.runtime.model.pdfs.get_instance_title(pdf_id)
			var pdf_display_name: String = pdf_instance_title if not pdf_instance_title.is_empty() else str(pdf_asset.get("display_name", NotLightL10n.text("library.kind.pdf")))
			_pdf_toolbar.configure(pdf_display_name, pdf_source_available, session.runtime.model.pdfs.get_page_index(pdf_id), session.runtime.model.pdfs.get_page_count(pdf_id))
	if _video_toolbar != null:
		var video_id: int = _selected_video_id()
		if video_id > 0 and asset_library != null:
			var video_asset_id: String = session.runtime.model.videos.get_asset_id(video_id)
			var video_asset: Dictionary = asset_library.get_asset(video_asset_id)
			var playback_path: String = video_media.resolve_playback_path(video_asset_id) if video_media != null else asset_library.resolve_asset_path(video_asset_id)
			var video_source_available: bool = not video_asset.is_empty() and not playback_path.is_empty() and FileAccess.file_exists(playback_path)
			var video_instance_title: String = session.runtime.model.videos.get_instance_title(video_id)
			var video_display_name: String = video_instance_title if not video_instance_title.is_empty() else str(video_asset.get("display_name", NotLightL10n.text("board.asset.video")))
			_video_toolbar.configure(
				video_display_name,
				video_source_available,
				video_media != null and video_media.tools_available()
			)
	if _audio_toolbar != null:
		var audio_id: int = _selected_audio_id()
		if audio_id > 0 and asset_library != null:
			var audio_asset_id: String = session.runtime.model.audios.get_asset_id(audio_id)
			var audio_asset: Dictionary = asset_library.get_asset(audio_asset_id)
			var audio_source_path: String = asset_library.resolve_asset_path(audio_asset_id)
			# A valid source is enough to enable Play. Unsupported/native-large formats
			# are prepared only after the user actually opens the player.
			var audio_source_available: bool = not audio_asset.is_empty() and not audio_source_path.is_empty() and FileAccess.file_exists(audio_source_path)
			var audio_instance_title: String = session.runtime.model.audios.get_instance_title(audio_id)
			var audio_display_name: String = audio_instance_title if not audio_instance_title.is_empty() else str(audio_asset.get("display_name", NotLightL10n.text("board.asset.audio")))
			_audio_toolbar.configure(audio_display_name, audio_source_available)
	if _stroke_toolbar != null:
		_stroke_toolbar.update_context(session.runtime, context_ids)
	if _formula_toolbar != null:
		_formula_toolbar.update_context(session.runtime, context_ids)
	_reposition_context_toolbars()


func _reposition_context_toolbars() -> void:
	if session == null:
		return
	if telemetry != null:
		telemetry.record_developer_counter(&"context_repositions")
	var editor_blocks_context: bool = _formula_editor != null and _formula_editor.visible
	var entity_context_allowed: bool = session.runtime.tools.active_tool_id != BoardToolController.TOOL_DRAW and not editor_blocks_context
	var show_anchor: bool = _text_toolbar_should_show and entity_context_allowed and not _selection_has_mixed_entity_types()
	if _text_toolbar != null:
		_text_toolbar.set_toolbar_anchor(_text_toolbar_anchor, size, show_anchor)
	if _connector_toolbar != null:
		_connector_toolbar.set_toolbar_anchor(_text_toolbar_anchor, size, show_anchor)
	if _image_toolbar != null:
		_image_toolbar.set_toolbar_anchor(_text_toolbar_anchor, size, _selected_image_id() > 0 and show_anchor)
	if _pdf_toolbar != null:
		_pdf_toolbar.set_toolbar_anchor(_text_toolbar_anchor, size, _selected_pdf_id() > 0 and show_anchor)
	if _video_toolbar != null:
		_video_toolbar.set_toolbar_anchor(_text_toolbar_anchor, size, _selected_video_id() > 0 and show_anchor)
	if _audio_toolbar != null:
		_audio_toolbar.set_toolbar_anchor(_text_toolbar_anchor, size, _selected_audio_id() > 0 and show_anchor)
	if _stroke_toolbar != null:
		_stroke_toolbar.set_toolbar_anchor(_text_toolbar_anchor, size, _selected_stroke_id() > 0 and show_anchor)
	if _formula_toolbar != null:
		_formula_toolbar.set_toolbar_anchor(_text_toolbar_anchor, size, _selected_formula_id() > 0 and show_anchor)


func _developer_diagnostics_context() -> Dictionary:
	if session == null:
		return {}
	var model: BoardModel = session.runtime.model
	var primary_id: int = session.runtime.selection.primary_id
	var primary_type: String = ""
	if primary_id > 0 and model.contains(primary_id):
		primary_type = String(model.get_entity_type(primary_id))
	var visible_toolbars: int = 0
	visible_toolbars += 1 if _text_toolbar != null and _text_toolbar.visible else 0
	visible_toolbars += 1 if _connector_toolbar != null and _connector_toolbar.visible else 0
	visible_toolbars += 1 if _image_toolbar != null and _image_toolbar.visible else 0
	visible_toolbars += 1 if _pdf_toolbar != null and _pdf_toolbar.visible else 0
	visible_toolbars += 1 if _video_toolbar != null and _video_toolbar.visible else 0
	visible_toolbars += 1 if _audio_toolbar != null and _audio_toolbar.visible else 0
	visible_toolbars += 1 if _stroke_toolbar != null and _stroke_toolbar.visible else 0
	visible_toolbars += 1 if _formula_toolbar != null and _formula_toolbar.visible else 0
	var result: Dictionary = {
		"objects_total": model.entities.size(),
		"objects_text": model.text_blocks.size(),
		"objects_images": model.images.size(),
		"objects_pdfs": model.pdfs.size(),
		"objects_videos": model.videos.size(),
		"objects_audios": model.audios.size(),
		"objects_modules": model.modules.size(),
		"objects_strokes": model.strokes.size(),
		"objects_connectors": model.connectors.size(),
		"spatial_index_size": session.runtime.spatial_index.size(),
		"selection_count": session.runtime.selection.size(),
		"selection_primary_type": primary_type,
		"model_revision": model.revision,
		"stroke_revision": model.stroke_revision,
		"performance_profile": _performance_profile_name(),
		"context_anchor_requested": _text_toolbar_should_show,
		"context_visible_toolbars": visible_toolbars,
		"context_text_toolbar_visible": _text_toolbar != null and _text_toolbar.visible,
		"context_connector_toolbar_visible": _connector_toolbar != null and _connector_toolbar.visible,
		"context_image_toolbar_visible": _image_toolbar != null and _image_toolbar.visible,
		"context_video_toolbar_visible": _video_toolbar != null and _video_toolbar.visible,
		"context_audio_toolbar_visible": _audio_toolbar != null and _audio_toolbar.visible,
		"context_stroke_toolbar_visible": _stroke_toolbar != null and _stroke_toolbar.visible,
		"audio_players_active": _audio_player_pool.active_count() if _audio_player_pool != null else 0,
		"video_players_active": _video_player_pool.active_count() if _video_player_pool != null else 0,
		"module_surfaces_active": _module_surface_pool.active_count() if _module_surface_pool != null else 0,
		"module_surfaces_budget": _active_module_budget(),
		"voice_recording_active": voice_recording != null and voice_recording.is_recording(),
		"voice_pending_jobs": _pending_voice_jobs.size(),
		"voice_input_enabled": voice_recording != null and voice_recording.audio_input_enabled(),
		"voice_consent_state": settings.microphone_consent_state if settings != null else AppSettingsStore.MICROPHONE_CONSENT_UNKNOWN,
	}
	if _board_view != null:
		result.merge(_board_view.get_developer_diagnostics_snapshot(), true)
	if _note_surface_pool != null:
		result.merge(_note_surface_pool.get_developer_diagnostics_snapshot(), true)
	if _module_surface_pool != null:
		result.merge(_module_surface_pool.get_developer_diagnostics_snapshot(), true)
	if _video_player_pool != null:
		result.merge(_video_player_pool.get_developer_diagnostics_snapshot(), true)
	if _audio_player_pool != null:
		result.merge(_audio_player_pool.get_developer_diagnostics_snapshot(), true)
	if audio_media != null:
		result.merge(audio_media.get_developer_diagnostics_snapshot(), true)
	return result


func _performance_profile_name() -> String:
	if settings == null:
		return NotLightL10n.text("performance.unavailable")
	match settings.performance_profile:
		AppSettingsStore.PerformanceProfile.ECO:
			return NotLightL10n.text("settings.performance.profile_eco")
		AppSettingsStore.PerformanceProfile.BALANCED:
			return NotLightL10n.text("settings.performance.profile_balanced")
		AppSettingsStore.PerformanceProfile.PERFORMANCE:
			return NotLightL10n.text("settings.performance.profile_fast")
		AppSettingsStore.PerformanceProfile.CUSTOM:
			return NotLightL10n.text("settings.performance.profile_custom")
		_:
			return NotLightL10n.text("settings.performance.profile_auto")


func _open_text_color_popover(anchor_rect: Rect2, current_color: Color) -> void:
	if _color_popover == null:
		return
	_color_popover_mode = COLOR_POPOVER_TEXT
	_color_popover.show_for(anchor_rect, size, current_color, false, NotLightL10n.text("runtime.ui.board_screen.80c359a2a3"), TextContextToolbar.text_palette())


func _open_background_color_popover(anchor_rect: Rect2, current_color: Color) -> void:
	if _color_popover == null:
		return
	_color_popover_mode = COLOR_POPOVER_BACKGROUND
	_color_popover.show_for(anchor_rect, size, current_color, true, NotLightL10n.text("runtime.ui.board_screen.2b657afe6b"), TextContextToolbar.background_palette())


func _open_connector_color_popover(anchor_rect: Rect2, current_color: Color) -> void:
	if _color_popover == null:
		return
	_color_popover_mode = COLOR_POPOVER_CONNECTOR
	_color_popover.show_for(anchor_rect, size, current_color, false, NotLightL10n.text("runtime.ui.board_screen.8a534f90e4"), ConnectorContextToolbar.palette())



func _open_drawing_color_popover(anchor_rect: Rect2, current_color: Color) -> void:
	if _color_popover == null:
		return
	_color_popover_mode = COLOR_POPOVER_DRAWING
	_color_popover.show_for(anchor_rect, size, current_color, false, NotLightL10n.text("drawing.color_picker"), DrawingToolPalette.quick_color_presets())


func _open_stroke_color_popover(anchor_rect: Rect2, current_color: Color) -> void:
	if _color_popover == null:
		return
	_color_popover_mode = COLOR_POPOVER_STROKE
	_color_popover.show_for(anchor_rect, size, current_color, false, NotLightL10n.text("stroke.color_picker"), DrawingToolPalette.quick_color_presets())


func _open_formula_editor_color_popover(anchor_rect: Rect2, current_color: Color) -> void:
	if _color_popover == null or _formula_editor == null or not _formula_editor.visible:
		return
	_color_popover_mode = COLOR_POPOVER_FORMULA_EDITOR
	_color_popover.show_for(anchor_rect, size, current_color, false, NotLightL10n.text("formula.editor.color"), FormulaContextToolbar.palette())


func _open_formula_object_color_popover(anchor_rect: Rect2, current_color: Color) -> void:
	if _color_popover == null or _selected_formula_id() <= 0:
		return
	_color_popover_mode = COLOR_POPOVER_FORMULA_OBJECT
	_color_popover.show_for(anchor_rect, size, current_color, false, NotLightL10n.text("formula.editor.color"), FormulaContextToolbar.palette())

func _on_color_popover_committed(color: Color) -> void:
	match _color_popover_mode:
		COLOR_POPOVER_TEXT:
			if _text_toolbar != null:
				_text_toolbar.apply_text_color_from_popover(color)
		COLOR_POPOVER_BACKGROUND:
			if _text_toolbar != null:
				_text_toolbar.apply_background_color_from_popover(color)
		COLOR_POPOVER_CONNECTOR:
			_change_selected_connector_color(color)
			if _connector_toolbar != null:
				_connector_toolbar.apply_color_from_popover(color)
		COLOR_POPOVER_DRAWING:
			if _drawing_palette != null:
				_drawing_palette.apply_external_color(color)
		COLOR_POPOVER_STROKE:
			_change_selected_stroke_color(color)
			if _stroke_toolbar != null:
				_stroke_toolbar.apply_color(color)
		COLOR_POPOVER_FORMULA_EDITOR:
			if _formula_editor != null and _formula_editor.visible:
				_formula_editor.apply_color_from_popover(color)
		COLOR_POPOVER_FORMULA_OBJECT:
			_change_selected_formula_color(color)
			if _formula_toolbar != null:
				_formula_toolbar.apply_color_from_popover(color)
	_color_popover_mode = COLOR_POPOVER_NONE


func _on_color_popover_canceled() -> void:
	_color_popover_mode = COLOR_POPOVER_NONE


func _close_color_popover() -> void:
	if _color_popover != null and _color_popover.visible:
		_color_popover.hide_without_commit()
	_color_popover_mode = COLOR_POPOVER_NONE



func _selection_has_mixed_entity_types() -> bool:
	if session == null or session.runtime.selection.size() <= 1:
		return false
	var selected_ids: PackedInt64Array = session.runtime.selection.get_selected_ids()
	var expected_type: StringName = StringName()
	for entity_id: int in selected_ids:
		if not session.runtime.model.contains(entity_id):
			continue
		var entity_type: StringName = session.runtime.model.get_entity_type(entity_id)
		if expected_type == StringName():
			expected_type = entity_type
		elif entity_type != expected_type:
			return true
	return false


func _selected_formula_id() -> int:
	if session == null or session.runtime.selection.size() != 1:
		return 0
	var entity_id: int = session.runtime.selection.primary_id
	return entity_id if entity_id > 0 and session.runtime.model.formulas.contains(entity_id) else 0


func _selected_stroke_id() -> int:
	if session == null or session.runtime.selection.size() != 1:
		return 0
	var entity_id: int = session.runtime.selection.primary_id
	return entity_id if entity_id > 0 and session.runtime.model.strokes.contains(entity_id) else 0

func _selected_image_id() -> int:
	if session == null or session.runtime.selection.size() != 1:
		return 0
	var entity_id: int = session.runtime.selection.primary_id
	if entity_id <= 0 or not session.runtime.model.images.contains(entity_id):
		return 0
	return entity_id


func _selected_pdf_id() -> int:
	if session == null or session.runtime.selection.size() != 1:
		return 0
	var entity_id: int = session.runtime.selection.primary_id
	if entity_id <= 0 or not session.runtime.model.pdfs.contains(entity_id):
		return 0
	return entity_id


func _selected_video_id() -> int:
	if session == null or session.runtime.selection.size() != 1:
		return 0
	var entity_id: int = session.runtime.selection.primary_id
	if entity_id <= 0 or not session.runtime.model.videos.contains(entity_id):
		return 0
	return entity_id


func _selected_audio_id() -> int:
	if session == null or session.runtime.selection.size() != 1:
		return 0
	var entity_id: int = session.runtime.selection.primary_id
	if entity_id <= 0 or not session.runtime.model.audios.contains(entity_id):
		return 0
	return entity_id


func _open_selected_image_rename_dialog() -> void:
	var image_id: int = _selected_image_id()
	if image_id <= 0:
		return
	_open_instance_rename_dialog(image_id, BoardEntityTypes.IMAGE)


func _open_selected_pdf_rename_dialog() -> void:
	var pdf_id: int = _selected_pdf_id()
	if pdf_id <= 0:
		return
	_open_instance_rename_dialog(pdf_id, BoardEntityTypes.PDF)


func _open_selected_video_rename_dialog() -> void:
	var video_id: int = _selected_video_id()
	if video_id <= 0:
		return
	_open_instance_rename_dialog(video_id, BoardEntityTypes.VIDEO)


func _open_selected_audio_rename_dialog() -> void:
	var audio_id: int = _selected_audio_id()
	if audio_id <= 0:
		return
	_open_instance_rename_dialog(audio_id, BoardEntityTypes.AUDIO)


func _open_instance_rename_dialog(entity_id: int, type_id: StringName) -> void:
	if asset_library == null or _asset_rename_dialog == null or session == null:
		return
	var asset_id: String = ""
	var instance_title: String = ""
	var fallback_name: String = NotLightL10n.text("board.asset.image")
	var dialog_title: String = NotLightL10n.text("board.asset.rename_image")
	if type_id == BoardEntityTypes.PDF:
		asset_id = session.runtime.model.pdfs.get_asset_id(entity_id)
		instance_title = session.runtime.model.pdfs.get_instance_title(entity_id)
		fallback_name = NotLightL10n.text("library.kind.pdf")
		dialog_title = NotLightL10n.text("board.asset.rename_pdf")
	elif type_id == BoardEntityTypes.VIDEO:
		asset_id = session.runtime.model.videos.get_asset_id(entity_id)
		instance_title = session.runtime.model.videos.get_instance_title(entity_id)
		fallback_name = NotLightL10n.text("board.asset.video")
		dialog_title = NotLightL10n.text("board.asset.rename_video")
	elif type_id == BoardEntityTypes.AUDIO:
		asset_id = session.runtime.model.audios.get_asset_id(entity_id)
		instance_title = session.runtime.model.audios.get_instance_title(entity_id)
		fallback_name = NotLightL10n.text("board.asset.audio")
		dialog_title = NotLightL10n.text("board.asset.rename_audio")
	elif type_id == BoardEntityTypes.IMAGE:
		asset_id = session.runtime.model.images.get_asset_id(entity_id)
		instance_title = session.runtime.model.images.get_instance_title(entity_id)
	else:
		return
	var asset: Dictionary = asset_library.get_asset(asset_id)
	var global_name: String = str(asset.get("display_name", fallback_name))
	_pending_rename_entity_id = entity_id
	_asset_rename_dialog.open_dialog(
		dialog_title,
		NotLightL10n.text("board.asset.rename_instance_help", {"name": global_name}),
		instance_title,
		NotLightL10n.text("common.save"),
		true
	)


func _rename_selected_asset(new_name: String) -> void:
	if session == null or _pending_rename_entity_id <= 0:
		return
	var entity_id: int = _pending_rename_entity_id
	_pending_rename_entity_id = 0
	if not session.runtime.model.contains(entity_id):
		return
	var type_id: StringName = session.runtime.model.get_entity_type(entity_id)
	var before: String = ""
	if type_id == BoardEntityTypes.IMAGE:
		before = session.runtime.model.images.get_instance_title(entity_id)
	elif type_id == BoardEntityTypes.PDF:
		before = session.runtime.model.pdfs.get_instance_title(entity_id)
	elif type_id == BoardEntityTypes.VIDEO:
		before = session.runtime.model.videos.get_instance_title(entity_id)
	elif type_id == BoardEntityTypes.AUDIO:
		before = session.runtime.model.audios.get_instance_title(entity_id)
	else:
		return
	var after: String = new_name.strip_edges().left(160)
	if after == before:
		return
	var command: UpdateAssetInstanceTitleCommand = UpdateAssetInstanceTitleCommand.new(entity_id, before, after)
	if not session.execute_command(command):
		_show_error(NotLightL10n.text("board.asset.rename_failed"))
		return
	_refresh_context_toolbars()
	if _video_player_pool != null:
		_video_player_pool.refresh_player_names()
	if _audio_player_pool != null:
		_audio_player_pool.refresh_player_names()


func _show_previous_pdf_page() -> void:
	var pdf_id: int = _selected_pdf_id()
	if pdf_id > 0:
		_show_pdf_page(session.runtime.model.pdfs.get_page_index(pdf_id) - 1)


func _show_next_pdf_page() -> void:
	var pdf_id: int = _selected_pdf_id()
	if pdf_id > 0:
		_show_pdf_page(session.runtime.model.pdfs.get_page_index(pdf_id) + 1)


func _show_pdf_page(page_index: int) -> void:
	var pdf_id: int = _selected_pdf_id()
	if pdf_id <= 0:
		return
	if not _board_view.set_pdf_page(pdf_id, page_index):
		return
	_refresh_context_toolbars()


func _optimize_selected_video() -> void:
	var video_id: int = _selected_video_id()
	if video_id <= 0 or video_media == null:
		return
	var selected_asset_id: String = session.runtime.model.videos.get_asset_id(video_id)
	if not video_media.enqueue_optimization(selected_asset_id, "auto"):
		_show_error(NotLightL10n.text("runtime.ui.board_screen.3132b67ab2"))


func _open_image_import_dialog() -> void:
	if _image_import_dialog != null:
		_image_import_target_world = _board_view.get_view_center_world_position()
		_image_import_dialog.popup_centered_ratio(0.72)


func _on_image_files_selected(paths: PackedStringArray) -> void:
	_queue_image_files(paths, _image_import_target_world)


func _open_pdf_import_dialog() -> void:
	if _pdf_import_dialog != null:
		_pdf_import_target_world = _board_view.get_view_center_world_position()
		_pdf_import_dialog.popup_centered_ratio(0.72)


func _on_pdf_files_selected(paths: PackedStringArray) -> void:
	_queue_pdf_files(paths, _pdf_import_target_world)


func _open_video_import_dialog() -> void:
	if _video_import_dialog != null:
		_video_import_target_world = _board_view.get_view_center_world_position()
		_video_import_dialog.popup_centered_ratio(0.72)


func _on_video_files_selected(paths: PackedStringArray) -> void:
	_queue_video_files(paths, _video_import_target_world)


func _open_audio_import_dialog() -> void:
	if _audio_import_dialog != null:
		_audio_import_target_world = _board_view.get_view_center_world_position()
		_audio_import_dialog.popup_centered_ratio(0.72)


func _on_audio_files_selected(paths: PackedStringArray) -> void:
	_queue_audio_files(paths, _audio_import_target_world)


func _queue_image_files(paths: PackedStringArray, world_position: Vector2) -> void:
	if asset_library == null:
		return
	var image_paths: PackedStringArray = PackedStringArray()
	for path: String in paths:
		if AssetImportCapabilities.kind_for_path(path) == AssetKinds.IMAGE:
			image_paths.append(path)
	if image_paths.is_empty():
		_show_error(NotLightL10n.text("board.error.image_unrecognized"))
		return
	var job_ids: PackedStringArray = asset_library.import_files(image_paths)
	for index: int in range(job_ids.size()):
		_pending_image_jobs[job_ids[index]] = world_position + Vector2(24.0, 24.0) * float(index)


func _paste_from_system_clipboard() -> void:
	# Internal board copies take priority. Some desktop clipboard providers can
	# retain both text and image flavors, so checking the marker first prevents
	# a stale image flavor from hijacking an object paste.
	var clipboard_text: String = DisplayServer.clipboard_get()
	if clipboard_text == NativeBoardView.INTERNAL_CLIPBOARD_MARKER:
		_board_view.paste_clipboard()
		return
	if DisplayServer.clipboard_has_image():
		var image: Image = DisplayServer.clipboard_get_image()
		if image != null and not image.is_empty() and asset_library != null:
			var job_id: String = asset_library.import_image(image)
			if not job_id.is_empty():
				_pending_image_jobs[job_id] = _board_view.get_pointer_world_position()
			return
	if not clipboard_text.is_empty():
		_board_view.paste_external_text(clipboard_text, _board_view.get_pointer_world_position())


func _place_library_asset(asset_id: String) -> void:
	if asset_library == null:
		return
	var asset: Dictionary = asset_library.get_asset(asset_id)
	if asset.is_empty():
		_show_error(NotLightL10n.text("runtime.ui.board_screen.3b9f1609f0"))
		return
	var kind: int = int(asset.get("kind", AssetKinds.OTHER))
	var world_position: Vector2 = _board_view.get_view_center_world_position()
	if kind == AssetKinds.PDF:
		_queue_pdf_placement(asset_id, world_position)
	elif kind == AssetKinds.IMAGE:
		if image_cache == null:
			_show_error(NotLightL10n.text("runtime.ui.board_screen.c44befd4d3"))
			return
		_queue_asset_placement(asset_id, world_position)
	elif kind == AssetKinds.VIDEO:
		_queue_video_placement(asset_id, world_position)
	elif kind == AssetKinds.AUDIO:
		_queue_audio_placement(asset_id, world_position)
	elif kind == AssetKinds.NOTE:
		_place_note_portal(asset_id, world_position)
	else:
		_show_error(NotLightL10n.text("runtime.ui.board_screen.d4cbf110cc"))
		return
	_set_library_drawer_open(false)


func _place_library_note_workspace(asset_id: String) -> void:
	if asset_library == null or note_repository == null:
		_show_error(NotLightL10n.text("notes.error.unavailable"))
		return
	var asset: Dictionary = asset_library.get_asset(asset_id)
	if int(asset.get("kind", AssetKinds.OTHER)) != AssetKinds.NOTE or not note_repository.contains(asset_id):
		_show_error(NotLightL10n.text("notes.error.missing"))
		return
	var entity_id: int = _place_note_portal(asset_id, _board_view.get_view_center_world_position(), NotePortalStore.VIEW_WORKSPACE)
	if entity_id > 0 and _note_surface_pool != null:
		_note_surface_pool.activate(entity_id)
	_set_library_drawer_open(false)


func _on_files_dropped(paths: PackedStringArray) -> void:
	# Window.files_dropped is global to the application window. BoardScreen can
	# stay alive while the Hub is visible, so never consume Hub/Library drops from
	# an invisible board screen.
	if not is_visible_in_tree() or _board_view == null or paths.is_empty():
		return
	var image_paths: PackedStringArray = PackedStringArray()
	var pdf_paths: PackedStringArray = PackedStringArray()
	var video_paths: PackedStringArray = PackedStringArray()
	var audio_paths: PackedStringArray = PackedStringArray()
	var note_paths: PackedStringArray = PackedStringArray()
	for path: String in paths:
		var kind: int = AssetImportCapabilities.kind_for_path(path)
		if kind == AssetKinds.IMAGE:
			image_paths.append(path)
		elif kind == AssetKinds.PDF:
			pdf_paths.append(path)
		elif kind == AssetKinds.VIDEO:
			video_paths.append(path)
		elif kind == AssetKinds.AUDIO:
			audio_paths.append(path)
		elif kind == AssetKinds.NOTE:
			note_paths.append(path)
	var world_position: Vector2 = _board_view.get_pointer_world_position()
	if not image_paths.is_empty():
		_queue_image_files(image_paths, world_position)
	if not pdf_paths.is_empty():
		_queue_pdf_files(pdf_paths, world_position + Vector2(28.0, 28.0))
	if not video_paths.is_empty():
		_queue_video_files(video_paths, world_position + Vector2(28.0, 28.0))
	if not audio_paths.is_empty():
		_queue_audio_files(audio_paths, world_position + Vector2(56.0, 56.0))
	if not note_paths.is_empty():
		_queue_note_files(note_paths, world_position + Vector2(84.0, 84.0))
	if image_paths.is_empty() and pdf_paths.is_empty() and video_paths.is_empty() and audio_paths.is_empty() and note_paths.is_empty():
		_show_error(NotLightL10n.text("board.drop.unsupported"))


func _queue_pdf_files(paths: PackedStringArray, world_position: Vector2) -> void:
	if asset_library == null:
		return
	var pdf_paths: PackedStringArray = PackedStringArray()
	for path: String in paths:
		if AssetImportCapabilities.kind_for_path(path) == AssetKinds.PDF:
			pdf_paths.append(path)
	if pdf_paths.is_empty():
		_show_error(NotLightL10n.text("pdf.error.unrecognized"))
		return
	var job_ids: PackedStringArray = asset_library.import_files(pdf_paths)
	for index: int in range(job_ids.size()):
		_pending_pdf_jobs[job_ids[index]] = world_position + Vector2(28.0, 28.0) * float(index)


func _queue_video_files(paths: PackedStringArray, world_position: Vector2) -> void:
	if asset_library == null:
		return
	var video_paths: PackedStringArray = PackedStringArray()
	for path: String in paths:
		if AssetImportCapabilities.kind_for_path(path) == AssetKinds.VIDEO:
			video_paths.append(path)
	if video_paths.is_empty():
		return
	var job_ids: PackedStringArray = asset_library.import_files(video_paths)
	for index: int in range(job_ids.size()):
		_pending_video_jobs[job_ids[index]] = world_position + Vector2(28.0, 28.0) * float(index)


func _queue_audio_files(paths: PackedStringArray, world_position: Vector2) -> void:
	if asset_library == null:
		return
	var audio_paths: PackedStringArray = PackedStringArray()
	for path: String in paths:
		if AssetImportCapabilities.kind_for_path(path) == AssetKinds.AUDIO:
			audio_paths.append(path)
	if audio_paths.is_empty():
		_show_error(NotLightL10n.text("board.error.audio_unrecognized"))
		return
	var job_ids: PackedStringArray = asset_library.import_files(audio_paths)
	for index: int in range(job_ids.size()):
		_pending_audio_jobs[job_ids[index]] = world_position + Vector2(24.0, 24.0) * float(index)


func _queue_note_files(paths: PackedStringArray, world_position: Vector2) -> void:
	if asset_library == null:
		return
	var note_paths: PackedStringArray = PackedStringArray()
	for path: String in paths:
		if AssetImportCapabilities.kind_for_path(path) == AssetKinds.NOTE:
			note_paths.append(path)
	if note_paths.is_empty():
		return
	var job_ids: PackedStringArray = asset_library.import_files(note_paths)
	for index: int in range(job_ids.size()):
		_pending_note_jobs[job_ids[index]] = world_position + Vector2(24.0, 24.0) * float(index)


func _place_note_portal(
	note_id: String,
	world_position: Vector2,
	view_mode: int = NotePortalStore.VIEW_PREVIEW
) -> int:
	if note_repository == null or not note_repository.contains(note_id):
		_show_error(NotLightL10n.text("notes.error.missing"))
		return 0
	var created_id: int = _board_view.create_note_portal(note_id, world_position, view_mode)
	if created_id <= 0:
		_show_error(NotLightL10n.text("board.error.note_create"))
		return 0
	_set_library_drawer_open(false)
	return created_id


func _queue_pdf_placement(asset_id: String, world_position: Vector2) -> void:
	if pdf_media == null:
		_show_error(NotLightL10n.text("pdf.error.service"))
		return
	var info: Dictionary = pdf_media.ensure_document(asset_id)
	if not bool(info.get("ok", false)):
		_show_error(str(info.get("error", NotLightL10n.text("pdf.error.metadata"))))
		return
	if bool(info.get("encrypted", false)):
		_show_error(NotLightL10n.text("pdf.error.encrypted_unsupported"))
		return
	var page_count: int = maxi(0, int(info.get("page_count", 0)))
	if page_count <= 0:
		var pending_value: Variant = _pending_pdf_placements.get(asset_id, [])
		var pending: Array[Vector2] = []
		if pending_value is Array:
			for raw_position: Variant in pending_value as Array:
				if raw_position is Vector2:
					pending.append(raw_position as Vector2)
		pending.append(world_position)
		_pending_pdf_placements[asset_id] = pending
		return
	_create_pdf_object(asset_id, world_position, info)


func _create_pdf_object(asset_id: String, world_position: Vector2, info: Dictionary) -> void:
	var page_size_value: Variant = info.get("page_size", PdfStore.DEFAULT_PAGE_SIZE)
	var page_size: Vector2i = page_size_value as Vector2i if page_size_value is Vector2i else PdfStore.DEFAULT_PAGE_SIZE
	var created_id: int = _board_view.create_pdf_from_asset(asset_id, maxi(1, int(info.get("page_count", 1))), page_size, world_position)
	if created_id <= 0:
		_show_error(NotLightL10n.text("pdf.error.create"))
		return
	_set_library_drawer_open(false)


func _on_pdf_document_ready(asset_id: String, info: Dictionary) -> void:
	var encrypted: bool = bool(info.get("encrypted", false))
	if session != null:
		var page_size_value: Variant = info.get("page_size", PdfStore.DEFAULT_PAGE_SIZE)
		var page_size: Vector2i = page_size_value as Vector2i if page_size_value is Vector2i else PdfStore.DEFAULT_PAGE_SIZE
		var page_count: int = maxi(1, int(info.get("page_count", 1)))
		for entity_id: int in session.runtime.model.pdfs.entity_ids:
			if session.runtime.model.pdfs.get_asset_id(entity_id) == asset_id:
				session.runtime.model.pdfs.update_document_info(entity_id, page_count, page_size)
	if _pending_pdf_placements.has(asset_id):
		var pending_value: Variant = _pending_pdf_placements.get(asset_id)
		_pending_pdf_placements.erase(asset_id)
		if encrypted:
			_show_error(NotLightL10n.text("pdf.error.encrypted_unsupported"))
		elif pending_value is Array:
			for raw_position: Variant in pending_value as Array:
				if raw_position is Vector2:
					_create_pdf_object(asset_id, raw_position as Vector2, info)
	_refresh_context_toolbars()


func _on_pdf_preparation_failed(asset_id: String, message: String) -> void:
	if _pending_pdf_placements.has(asset_id):
		_pending_pdf_placements.erase(asset_id)
		_show_error(message)


func _queue_video_placement(asset_id: String, world_position: Vector2) -> void:
	if video_media == null:
		_show_error(NotLightL10n.text("runtime.ui.board_screen.f6033a3bea"))
		return
	var metadata: Dictionary = video_media.ensure_asset(asset_id)
	if not bool(metadata.get("ok", false)):
		_show_error(str(metadata.get("error", NotLightL10n.text("runtime.ui.board_screen.3c855ca773"))))
		return
	var pixel_size: Vector2i = Vector2i(
		maxi(1, int(metadata.get("width", VideoStore.DEFAULT_PIXEL_SIZE.x))),
		maxi(1, int(metadata.get("height", VideoStore.DEFAULT_PIXEL_SIZE.y)))
	)
	var duration_seconds: float = maxf(0.0, float(metadata.get("duration", 0.0)))
	var created_id: int = _board_view.create_video_from_asset(
		asset_id,
		pixel_size,
		duration_seconds,
		world_position
	)
	if created_id <= 0:
		_show_error(NotLightL10n.text("runtime.ui.board_screen.a8f9c7b065"))
		return
	_set_library_drawer_open(false)


func _queue_audio_placement(asset_id: String, world_position: Vector2, known_duration: float = -1.0) -> void:
	if audio_media == null:
		_show_error(NotLightL10n.text("board.error.audio_service"))
		return
	var metadata: Dictionary = audio_media.ensure_asset(asset_id)
	if metadata.is_empty() or not bool(metadata.get("ok", false)):
		_show_error(str(metadata.get("error", NotLightL10n.text("board.error.audio_metadata"))))
		return
	var duration_seconds: float = known_duration if known_duration >= 0.0 else maxf(0.0, float(metadata.get("duration", 0.0)))
	var created_id: int = _board_view.create_audio_from_asset(asset_id, duration_seconds, world_position)
	if created_id <= 0:
		_show_error(NotLightL10n.text("board.error.audio_create"))
		return
	_set_library_drawer_open(false)


func _open_board_video(asset_id: String, entity_id: int) -> void:
	if _video_player_pool == null or video_media == null:
		_show_error(NotLightL10n.text("runtime.ui.board_screen.2c9cb2b275"))
		return
	_video_player_pool.activate(entity_id, asset_id)


func _open_board_audio(asset_id: String, entity_id: int) -> void:
	if _audio_player_pool == null or audio_media == null:
		_show_error(NotLightL10n.text("board.error.audio_player"))
		return
	if not _audio_player_pool.activate(entity_id, asset_id):
		return


func _play_selected_audio() -> void:
	var audio_id: int = _selected_audio_id()
	if audio_id <= 0 or session == null:
		return
	_open_board_audio(session.runtime.model.audios.get_asset_id(audio_id), audio_id)


func _on_import_job_failed(job_id: String, _source_path: String, message: String) -> void:
	var was_pending: bool = false
	if _pending_image_jobs.has(job_id):
		_pending_image_jobs.erase(job_id)
		was_pending = true
	if _pending_pdf_jobs.has(job_id):
		_pending_pdf_jobs.erase(job_id)
		was_pending = true
	if _pending_video_jobs.has(job_id):
		_pending_video_jobs.erase(job_id)
		was_pending = true
	if _pending_audio_jobs.has(job_id):
		_pending_audio_jobs.erase(job_id)
		was_pending = true
	if _pending_note_jobs.has(job_id):
		_pending_note_jobs.erase(job_id)
		was_pending = true
	if was_pending:
		_show_error(message)


func _on_import_job_finished(job_id: String, asset_id: String, _duplicate: bool) -> void:
	if _pending_image_jobs.has(job_id):
		var image_position: Variant = _pending_image_jobs.get(job_id)
		_pending_image_jobs.erase(job_id)
		if image_position is Vector2:
			_queue_asset_placement(asset_id, image_position as Vector2)
		return
	if _pending_pdf_jobs.has(job_id):
		var pdf_position: Variant = _pending_pdf_jobs.get(job_id)
		_pending_pdf_jobs.erase(job_id)
		if pdf_position is Vector2:
			_queue_pdf_placement(asset_id, pdf_position as Vector2)
		return
	if _pending_video_jobs.has(job_id):
		var video_position: Variant = _pending_video_jobs.get(job_id)
		_pending_video_jobs.erase(job_id)
		if video_position is Vector2:
			_queue_video_placement(asset_id, video_position as Vector2)
		return
	if _pending_audio_jobs.has(job_id):
		var audio_position: Variant = _pending_audio_jobs.get(job_id)
		_pending_audio_jobs.erase(job_id)
		if audio_position is Vector2:
			_queue_audio_placement(asset_id, audio_position as Vector2)
		return
	if _pending_note_jobs.has(job_id):
		var note_position: Variant = _pending_note_jobs.get(job_id)
		_pending_note_jobs.erase(job_id)
		if note_position is Vector2:
			_place_note_portal(asset_id, note_position as Vector2)


func _toggle_voice_recording() -> void:
	if voice_recording == null:
		_set_voice_recording_ui(false)
		_show_error(NotLightL10n.text("board.error.voice_service"))
		return
	if voice_recording.is_recording():
		_stop_voice_recording()
		return
	if settings == null or settings.microphone_consent_state != AppSettingsStore.MICROPHONE_CONSENT_ALLOWED:
		_set_voice_recording_ui(false)
		_open_microphone_permission_dialog()
		return
	_start_voice_recording_after_consent()


func _open_microphone_permission_dialog() -> void:
	if _microphone_permission_dialog == null or voice_recording == null:
		return
	_microphone_permission_dialog.open_dialog(
		voice_recording.can_open_system_microphone_settings(),
		voice_recording.audio_input_enabled()
	)


func _on_microphone_permission_allowed() -> void:
	if settings != null:
		settings.set_microphone_consent_state(AppSettingsStore.MICROPHONE_CONSENT_ALLOWED)
	_start_voice_recording_after_consent()


func _on_microphone_permission_declined() -> void:
	if settings != null:
		settings.set_microphone_consent_state(AppSettingsStore.MICROPHONE_CONSENT_DECLINED)
	_set_voice_recording_ui(false)


func _open_system_microphone_settings() -> void:
	if voice_recording == null or not voice_recording.open_system_microphone_settings():
		_show_error(NotLightL10n.text("voice.permission.system_settings_failed"))


func _start_voice_recording_after_consent() -> void:
	if voice_recording == null:
		return
	if not voice_recording.audio_input_enabled():
		_set_voice_recording_ui(false)
		_show_error(NotLightL10n.text("voice.error.input_disabled"))
		_open_microphone_permission_dialog()
		return
	_voice_record_target_world = _board_view.get_view_center_world_position()
	if not voice_recording.start_recording():
		_set_voice_recording_ui(false)


func _stop_voice_recording() -> void:
	if voice_recording == null or not voice_recording.is_recording():
		return
	var target: Vector2 = _voice_record_target_world
	var job_id: String = voice_recording.stop_recording()
	if job_id.is_empty():
		return
	_pending_voice_jobs[job_id] = target
	_set_voice_recording_ui(false)


func _cancel_voice_recording() -> void:
	if voice_recording != null and voice_recording.is_recording():
		voice_recording.cancel_recording()
	_set_voice_recording_ui(false)


func _on_voice_recording_started() -> void:
	_set_voice_recording_ui(true)
	_refresh_voice_recording_label()


func _on_voice_recording_cancelled() -> void:
	_set_voice_recording_ui(false)


func _on_voice_recording_failed(message: String) -> void:
	_set_voice_recording_ui(false)
	_show_error(message)
	# When capture produced only silence (or the input driver could not be set up),
	# put the recovery actions one click away instead of letting the user retry the
	# same failing recording loop with no route to the OS privacy settings.
	if voice_recording != null and voice_recording.needs_microphone_attention():
		call_deferred("_open_microphone_permission_dialog")


func _on_voice_import_finished(job_id: String, asset_id: String, duration_seconds: float, duplicate: bool) -> void:
	var target: Vector2 = _board_view.get_view_center_world_position()
	var stored: Variant = _pending_voice_jobs.get(job_id)
	if stored is Vector2:
		target = stored as Vector2
	_pending_voice_jobs.erase(job_id)
	# Voice captures should look like first-class library assets rather than
	# temporary WAV filenames. Never rename a deduplicated pre-existing asset.
	if not duplicate and asset_library != null:
		var voice_name: String = NotLightL10n.text("board.voice.note_name")
		if not voice_name.is_empty():
			asset_library.rename_asset(asset_id, voice_name)
	_queue_audio_placement(asset_id, target, duration_seconds)


func _on_voice_import_failed(job_id: String, message: String) -> void:
	_pending_voice_jobs.erase(job_id)
	_show_error(message)


func _set_voice_recording_ui(active: bool) -> void:
	if _voice_record_panel != null:
		_voice_record_panel.visible = active
	if _voice_record_button != null:
		_voice_record_button.button_pressed = active if _voice_record_button.toggle_mode else false
	if _voice_record_timer != null:
		if active:
			_voice_record_timer.start()
		else:
			_voice_record_timer.stop()


func _refresh_voice_recording_label() -> void:
	if _voice_record_label == null or voice_recording == null:
		return
	_voice_record_label.text = NotLightL10n.text("voice.recording_label", {"time": _format_duration(voice_recording.elapsed_seconds())})


func _format_duration(seconds: float) -> String:
	var total: int = maxi(0, int(floor(seconds)))
	var minutes: int = total / 60
	var secs: int = total % 60
	return NotLightL10n.text("ui.format.time_ms") % [minutes, secs]


func _on_audio_preparation_failed(_asset_id: String, _message: String) -> void:
	# Player/context UI surfaces format errors on demand. Waveform generation is a
	# best-effort enhancement and must not spam passive board interaction.
	_refresh_context_toolbars()


func _on_audio_playback_ready(_asset_id: String, _playback_path: String) -> void:
	_refresh_context_toolbars()


func _queue_asset_placement(asset_id: String, world_position: Vector2) -> void:
	if image_cache == null:
		return
	var intrinsic: Vector2i = image_cache.get_intrinsic_size(asset_id)
	if intrinsic.x > 0 and intrinsic.y > 0:
		_board_view.create_image_from_asset(asset_id, intrinsic, world_position)
		_set_library_drawer_open(false)
		return
	var positions: Array[Vector2] = []
	var existing: Variant = _pending_asset_placements.get(asset_id)
	if existing is Array:
		for raw_position: Variant in (existing as Array):
			if raw_position is Vector2:
				positions.append(raw_position as Vector2)
	positions.append(world_position)
	_pending_asset_placements[asset_id] = positions
	image_cache.request_metadata(asset_id)


func _on_image_texture_ready(asset_id: String) -> void:
	if not _pending_asset_placements.has(asset_id) or image_cache == null:
		return
	var intrinsic: Vector2i = image_cache.get_intrinsic_size(asset_id)
	if intrinsic.x <= 0 or intrinsic.y <= 0:
		return
	var raw_positions: Variant = _pending_asset_placements.get(asset_id)
	_pending_asset_placements.erase(asset_id)
	if raw_positions is Array:
		for raw_position: Variant in (raw_positions as Array):
			if raw_position is Vector2:
				_board_view.create_image_from_asset(asset_id, intrinsic, raw_position as Vector2)
	_set_library_drawer_open(false)


func _on_image_texture_failed(asset_id: String, message: String) -> void:
	if _pending_asset_placements.has(asset_id):
		_pending_asset_placements.erase(asset_id)
		_show_error(message)



func _on_drawing_brush_changed(style_id: int, color: Color, width: float, spray_spread: float, eraser_enabled: bool, eraser_radius: float) -> void:
	_board_view.set_drawing_brush(style_id, color, width, spray_spread, eraser_enabled, eraser_radius)


func _change_selected_stroke_width(width: float) -> void:
	var entity_id: int = _selected_stroke_id()
	if entity_id <= 0:
		return
	var command: UpdateStrokeStyleCommand = UpdateStrokeStyleCommand.new(
		session.runtime, entity_id,
		session.runtime.model.strokes.get_style_id(entity_id),
		session.runtime.model.strokes.get_color(entity_id), width,
		session.runtime.model.strokes.get_spray_spread(entity_id)
	)
	session.execute_command(command)


func _change_selected_stroke_spread(spread: float) -> void:
	var entity_id: int = _selected_stroke_id()
	if entity_id <= 0:
		return
	var current_bounds: Rect2 = session.runtime.model.get_entity_bounds(entity_id)
	var command: UpdateStrokeStyleCommand = UpdateStrokeStyleCommand.new(
		session.runtime, entity_id,
		session.runtime.model.strokes.get_style_id(entity_id),
		session.runtime.model.strokes.get_color(entity_id),
		session.runtime.model.strokes.get_effective_width(entity_id, current_bounds),
		spread
	)
	session.execute_command(command)


func _change_selected_stroke_color(color: Color) -> void:
	var entity_id: int = _selected_stroke_id()
	if entity_id <= 0:
		return
	var current_bounds: Rect2 = session.runtime.model.get_entity_bounds(entity_id)
	var command: UpdateStrokeStyleCommand = UpdateStrokeStyleCommand.new(
		session.runtime, entity_id,
		session.runtime.model.strokes.get_style_id(entity_id),
		color, session.runtime.model.strokes.get_effective_width(entity_id, current_bounds),
		session.runtime.model.strokes.get_spray_spread(entity_id)
	)
	session.execute_command(command)


func _layout_status_controls() -> void:
	if _status_panel == null or _monitor_panel == null or _developer_panel_container == null:
		return
	const MARGIN: float = 18.0
	const GAP: float = 10.0
	# Zoom owns the bottom-right corner. On very narrow windows its nonessential
	# Reset text is the first thing to collapse; performance metrics can only use
	# the remaining space to the LEFT and never displace the zoom control.
	if _zoom_reset_button != null:
		_zoom_reset_button.visible = size.x >= 430.0
	var zoom_size: Vector2 = _status_panel.get_combined_minimum_size()
	zoom_size.x = minf(maxf(144.0, zoom_size.x), maxf(144.0, size.x - MARGIN * 2.0))
	zoom_size.y = maxf(48.0, zoom_size.y)
	_status_panel.position = Vector2(maxf(MARGIN, size.x - MARGIN - zoom_size.x), maxf(MARGIN, size.y - MARGIN - zoom_size.y))
	_status_panel.size = zoom_size
	var available_width: float = maxf(0.0, _status_panel.position.x - GAP - MARGIN)
	if _monitor_strip != null:
		_monitor_strip.set_maximum_width(available_width)
	var monitor_size: Vector2 = _monitor_panel.get_combined_minimum_size()
	_monitor_panel.visible = _monitor_strip != null and _monitor_strip.visible and available_width >= 70.0
	if _monitor_panel.visible:
		monitor_size.x = minf(monitor_size.x, available_width)
		monitor_size.y = maxf(48.0, monitor_size.y)
		_monitor_panel.position = Vector2(maxf(MARGIN, _status_panel.position.x - GAP - monitor_size.x), _status_panel.position.y)
		_monitor_panel.size = monitor_size

	# Developer telemetry is opt-in and deliberately occupies a separate row.
	# It never changes the normal bottom controls and is hidden on windows that
	# cannot fit a useful diagnostics line without covering the workspace.
	var diagnostics_available_width: float = maxf(0.0, size.x - MARGIN * 2.0)
	var diagnostics_requested: bool = _developer_panel != null and _developer_panel.visible
	_developer_panel_container.visible = diagnostics_requested and diagnostics_available_width >= 440.0
	if _developer_panel_container.visible:
		var diagnostics_size: Vector2 = _developer_panel_container.get_combined_minimum_size()
		diagnostics_size.x = minf(maxf(420.0, diagnostics_size.x), diagnostics_available_width)
		var bottom_controls_top: float = _status_panel.position.y
		if _monitor_panel.visible:
			bottom_controls_top = minf(bottom_controls_top, _monitor_panel.position.y)
		diagnostics_size.y = maxf(74.0, diagnostics_size.y)
		_developer_panel_container.position = Vector2(
			maxf(MARGIN, size.x - MARGIN - diagnostics_size.x),
			maxf(MARGIN, bottom_controls_top - GAP - diagnostics_size.y)
		)
		_developer_panel_container.size = diagnostics_size


func _selected_connector_id() -> int:
	if session == null or session.runtime.selection.size() != 1:
		return 0
	var entity_id: int = session.runtime.selection.primary_id
	return entity_id if session.runtime.model.connectors.contains(entity_id) else 0


func _change_selected_connector_color(color: Color) -> void:
	var connector_id: int = _selected_connector_id()
	if session == null or connector_id <= 0:
		return
	var before: Dictionary = session.runtime.model.connectors.get_record(connector_id)
	var after: Dictionary = before.duplicate(true)
	after["color"] = color.to_html(true)
	if after == before:
		return
	var command: UpdateConnectorCommand = UpdateConnectorCommand.new(connector_id, before, after, NotLightL10n.text("runtime.ui.board_screen.8a534f90e4"))
	session.runtime.commands.execute(command, session.runtime)


func _change_selected_connector_direction(direction: int) -> void:
	var connector_id: int = _selected_connector_id()
	if session == null or connector_id <= 0:
		return
	var safe_direction: int = clampi(direction, ConnectorStore.DIRECTION_NONE, ConnectorStore.DIRECTION_BOTH)
	var before: Dictionary = session.runtime.model.connectors.get_record(connector_id)
	if int(before.get("direction", ConnectorStore.DEFAULT_DIRECTION)) == safe_direction:
		return
	var after: Dictionary = before.duplicate(true)
	after["direction"] = safe_direction
	var command: UpdateConnectorCommand = UpdateConnectorCommand.new(connector_id, before, after, NotLightL10n.text("runtime.ui.board_screen.aa891d7fe0"))
	session.runtime.commands.execute(command, session.runtime)


func _selected_text_ids() -> PackedInt64Array:
	var result: PackedInt64Array = PackedInt64Array()
	if session == null:
		return result
	for entity_id: int in session.runtime.selection.get_selected_ids():
		if (
			session.runtime.model.get_entity_type(entity_id) == BoardEntityTypes.TEXT
			and session.runtime.model.text_blocks.contains(entity_id)
		):
			result.append(entity_id)
	return result


func _set_selected_font_family(font_family: String) -> void:
	if _editing_text_entity_id > 0:
		_board_view.apply_editor_font_family(font_family)
		return
	var ids: PackedInt64Array = _selected_text_ids()
	if session == null or ids.is_empty():
		return
	var before: Array[Dictionary] = []
	var after: Array[Dictionary] = []
	var changed_ids: PackedInt64Array = PackedInt64Array()
	for entity_id: int in ids:
		var previous: Dictionary = session.runtime.model.text_blocks.get_record(entity_id)
		if str(previous.get("font_family", TextBlockStore.DEFAULT_FONT_FAMILY)) == font_family:
			continue
		var next: Dictionary = previous.duplicate(true)
		next["font_family"] = font_family
		changed_ids.append(entity_id)
		before.append(previous)
		after.append(next)
	_execute_text_property_command(changed_ids, before, after, NotLightL10n.text("asset.kind.font"), true)


func _set_selected_font_size(font_size: float) -> void:
	var safe_size: float = clampf(font_size, TextBlockStore.MIN_FONT_SIZE, TextBlockStore.MAX_FONT_SIZE)
	if _editing_text_entity_id > 0:
		_board_view.apply_editor_font_size(safe_size)
		return
	var ids: PackedInt64Array = _selected_text_ids()
	if session == null or ids.is_empty():
		return
	var changed_ids: PackedInt64Array = PackedInt64Array()
	var before: Array[Dictionary] = []
	var after: Array[Dictionary] = []
	for entity_id: int in ids:
		var previous: Dictionary = session.runtime.model.text_blocks.get_record(entity_id)
		if is_equal_approx(float(previous.get("font_size", TextBlockStore.DEFAULT_FONT_SIZE)), safe_size):
			continue
		var next: Dictionary = previous.duplicate(true)
		next["font_size"] = safe_size
		changed_ids.append(entity_id)
		before.append(previous)
		after.append(next)
	_execute_text_property_command(changed_ids, before, after, NotLightL10n.text("runtime.ui.board_screen.b1e23e1ff0"), true)


func _change_selected_font_style(style_flag: int, enabled: bool) -> void:
	if _editing_text_entity_id > 0:
		_board_view.apply_editor_style_flag(style_flag, enabled)
		return
	var ids: PackedInt64Array = _selected_text_ids()
	if session == null or ids.is_empty():
		return
	var changed_ids: PackedInt64Array = PackedInt64Array()
	var before: Array[Dictionary] = []
	var after: Array[Dictionary] = []
	for entity_id: int in ids:
		var previous: Dictionary = session.runtime.model.text_blocks.get_record(entity_id)
		var next: Dictionary = previous.duplicate(true)
		var flags: int = int(next.get("base_style_flags", 0))
		if enabled:
			flags |= style_flag
		else:
			flags &= ~style_flag
		next["base_style_flags"] = flags & TextBlockStore.FONT_STYLE_ALL
		var runs: Array = next.get("style_runs", []) as Array
		for raw_run: Variant in runs:
			if raw_run is not Dictionary:
				continue
			var run: Dictionary = raw_run as Dictionary
			var run_flags: int = int(run.get("flags", 0))
			if enabled:
				run_flags |= style_flag
			else:
				run_flags &= ~style_flag
			run["flags"] = run_flags & TextBlockStore.FONT_STYLE_ALL
		next["style_runs"] = runs
		if next == previous:
			continue
		changed_ids.append(entity_id)
		before.append(previous)
		after.append(next)
	_execute_text_property_command(changed_ids, before, after, NotLightL10n.text("runtime.ui.board_screen.63a10b583e"), true)


func _change_selected_alignment(alignment: HorizontalAlignment) -> void:
	if _editing_text_entity_id > 0:
		_board_view.apply_editor_alignment(alignment)
		return
	var ids: PackedInt64Array = _selected_text_ids()
	if session == null or ids.is_empty():
		return
	var changed_ids: PackedInt64Array = PackedInt64Array()
	var before: Array[Dictionary] = []
	var after: Array[Dictionary] = []
	for entity_id: int in ids:
		var previous: Dictionary = session.runtime.model.text_blocks.get_record(entity_id)
		if int(previous.get("alignment", HORIZONTAL_ALIGNMENT_LEFT)) == int(alignment):
			continue
		var next: Dictionary = previous.duplicate(true)
		next["alignment"] = int(alignment)
		changed_ids.append(entity_id)
		before.append(previous)
		after.append(next)
	_execute_text_property_command(changed_ids, before, after, NotLightL10n.text("runtime.ui.board_screen.b74b8d15dc"), false)


func _change_selected_list_type(list_type: int) -> void:
	var safe_type: int = clampi(list_type, TextBlockStore.LIST_NONE, TextBlockStore.LIST_NUMBERED)
	if _editing_text_entity_id > 0:
		_board_view.apply_editor_list_type(safe_type)
		return
	var ids: PackedInt64Array = _selected_text_ids()
	if session == null or ids.is_empty():
		return
	var changed_ids: PackedInt64Array = PackedInt64Array()
	var before: Array[Dictionary] = []
	var after: Array[Dictionary] = []
	for entity_id: int in ids:
		var previous: Dictionary = session.runtime.model.text_blocks.get_record(entity_id)
		var next: Dictionary = previous.duplicate(true)
		var paragraphs: Array = _normalized_record_paragraphs(next)
		for raw_paragraph: Variant in paragraphs:
			if raw_paragraph is Dictionary:
				var paragraph: Dictionary = raw_paragraph as Dictionary
				paragraph["list_type"] = safe_type
				if safe_type == TextBlockStore.LIST_NONE:
					paragraph["indent"] = 0
		next["paragraphs"] = paragraphs
		if next == previous:
			continue
		changed_ids.append(entity_id)
		before.append(previous)
		after.append(next)
	_execute_text_property_command(changed_ids, before, after, NotLightL10n.text("runtime.ui.board_screen.a21729ad14"), true)


func _change_selected_list_indent(delta: int) -> void:
	if delta == 0:
		return
	if _editing_text_entity_id > 0:
		_board_view.adjust_editor_list_indent(delta)
		return
	var ids: PackedInt64Array = _selected_text_ids()
	if session == null or ids.is_empty():
		return
	var changed_ids: PackedInt64Array = PackedInt64Array()
	var before: Array[Dictionary] = []
	var after: Array[Dictionary] = []
	for entity_id: int in ids:
		var previous: Dictionary = session.runtime.model.text_blocks.get_record(entity_id)
		var next: Dictionary = previous.duplicate(true)
		var paragraphs: Array = _normalized_record_paragraphs(next)
		for raw_paragraph: Variant in paragraphs:
			if raw_paragraph is not Dictionary:
				continue
			var paragraph: Dictionary = raw_paragraph as Dictionary
			if int(paragraph.get("list_type", TextBlockStore.LIST_NONE)) == TextBlockStore.LIST_NONE:
				continue
			paragraph["indent"] = clampi(int(paragraph.get("indent", 0)) + delta, 0, TextBlockStore.MAX_LIST_INDENT)
		next["paragraphs"] = paragraphs
		if next == previous:
			continue
		changed_ids.append(entity_id)
		before.append(previous)
		after.append(next)
	_execute_text_property_command(changed_ids, before, after, NotLightL10n.text("runtime.ui.board_screen.40c4894efa"), true)


func _change_selected_text_color(color: Color) -> void:
	if _editing_text_entity_id > 0:
		_board_view.apply_editor_text_color(color)
		return
	var ids: PackedInt64Array = _selected_text_ids()
	if session == null or ids.is_empty():
		return
	var changed_ids: PackedInt64Array = PackedInt64Array()
	var before: Array[Dictionary] = []
	var after: Array[Dictionary] = []
	for entity_id: int in ids:
		var previous: Dictionary = session.runtime.model.text_blocks.get_record(entity_id)
		var next: Dictionary = previous.duplicate(true)
		next["text_color"] = color.to_html(true)
		var runs: Array = next.get("style_runs", []) as Array
		for raw_run: Variant in runs:
			if raw_run is Dictionary:
				(raw_run as Dictionary)["color"] = color.to_html(true)
		next["style_runs"] = runs
		if next == previous:
			continue
		changed_ids.append(entity_id)
		before.append(previous)
		after.append(next)
	_execute_text_property_command(changed_ids, before, after, NotLightL10n.text("runtime.ui.board_screen.80c359a2a3"), false)


func _change_selected_background_color(color: Color) -> void:
	if _editing_text_entity_id > 0:
		_board_view.apply_editor_background_color(color)
		return
	var ids: PackedInt64Array = _selected_text_ids()
	if session == null or ids.is_empty():
		return
	var changed_ids: PackedInt64Array = PackedInt64Array()
	var before: Array[Dictionary] = []
	var after: Array[Dictionary] = []
	for entity_id: int in ids:
		var previous: Dictionary = session.runtime.model.text_blocks.get_record(entity_id)
		var next: Dictionary = previous.duplicate(true)
		next["background_color"] = color.to_html(true)
		if next == previous:
			continue
		changed_ids.append(entity_id)
		before.append(previous)
		after.append(next)
	_execute_text_property_command(changed_ids, before, after, NotLightL10n.text("runtime.ui.board_screen.2b657afe6b"), true)


func _change_selected_background_opacity(opacity: float) -> void:
	var safe_opacity: float = clampf(opacity, 0.0, 1.0)
	if _editing_text_entity_id > 0:
		_board_view.apply_editor_background_opacity(safe_opacity)
		return
	var ids: PackedInt64Array = _selected_text_ids()
	if session == null or ids.is_empty():
		return
	var changed_ids: PackedInt64Array = PackedInt64Array()
	var before: Array[Dictionary] = []
	var after: Array[Dictionary] = []
	for entity_id: int in ids:
		var previous: Dictionary = session.runtime.model.text_blocks.get_record(entity_id)
		var background: Color = Color.from_string(str(previous.get("background_color", Color.TRANSPARENT.to_html(true))), Color.TRANSPARENT)
		if background.a <= 0.001 and safe_opacity > 0.0:
			background = Color("#e8f4e8")
		background.a = safe_opacity
		var next: Dictionary = previous.duplicate(true)
		next["background_color"] = background.to_html(true)
		if next == previous:
			continue
		changed_ids.append(entity_id)
		before.append(previous)
		after.append(next)
	_execute_text_property_command(changed_ids, before, after, NotLightL10n.text("runtime.ui.board_screen.bd7b345fcd"), true)


func _execute_text_property_command(
	ids: PackedInt64Array,
	before: Array[Dictionary],
	after: Array[Dictionary],
	label: String,
	recalculate_bounds: bool
) -> void:
	if session == null or ids.is_empty() or ids.size() != before.size() or ids.size() != after.size():
		return
	var before_bounds: Array[Rect2] = []
	var after_bounds: Array[Rect2] = []
	if recalculate_bounds:
		for index: int in range(ids.size()):
			var entity_id: int = int(ids[index])
			var bounds: Rect2 = session.runtime.model.get_entity_bounds(entity_id)
			before_bounds.append(bounds)
			after_bounds.append(TextLayoutUtils.fit_record_bounds(bounds, after[index], TextLayoutUtils.DEFAULT_MINIMUM_SIZE))
	var command: UpdateTextPropertiesCommand = UpdateTextPropertiesCommand.new(
		ids,
		before,
		after,
		label,
		before_bounds,
		after_bounds
	)
	session.execute_command(command)


func _normalized_record_paragraphs(record: Dictionary) -> Array:
	var text: String = str(record.get("text", ""))
	var target_count: int = TextBlockStore.paragraph_count_for_text(text)
	var source: Array = record.get("paragraphs", []) as Array
	var result: Array = []
	for index: int in range(target_count):
		var list_type: int = TextBlockStore.LIST_NONE
		var indent: int = 0
		if index < source.size() and source[index] is Dictionary:
			var paragraph: Dictionary = source[index] as Dictionary
			list_type = clampi(int(paragraph.get("list_type", TextBlockStore.LIST_NONE)), TextBlockStore.LIST_NONE, TextBlockStore.LIST_NUMBERED)
			indent = clampi(int(paragraph.get("indent", 0)), 0, TextBlockStore.MAX_LIST_INDENT)
		result.append({"list_type": list_type, "indent": indent})
	return result


func _update_hint_text() -> void:
	if _hint_label == null:
		return
	var tool_id: StringName = BoardToolController.TOOL_SELECT
	if session != null:
		tool_id = session.runtime.tools.active_tool_id
	match tool_id:
		BoardToolController.TOOL_TEXT:
			NotLightL10n.bind_text(_hint_label, "board.hint.text")
		BoardToolController.TOOL_FORMULA:
			NotLightL10n.bind_text(_hint_label, "board.hint.formula")
		BoardToolController.TOOL_DRAW:
			NotLightL10n.bind_text(_hint_label, "board.hint.draw")
		BoardToolController.TOOL_SELECT:
			var primary_id: int = session.runtime.selection.primary_id if session != null else 0
			if session != null and primary_id > 0 and session.runtime.model.connectors.contains(primary_id):
				NotLightL10n.bind_text(_hint_label, "board.hint.connector")
			else:
				NotLightL10n.bind_text(_hint_label, "board.hint.select")
		_:
			var input_mode: int = int(settings.get_snapshot().get("input_mode", int(AppSettingsStore.InputMode.TRACKPAD))) if settings != null else int(AppSettingsStore.InputMode.TRACKPAD)
			_hint_label.text = (
				NotLightL10n.text("board.hint.hand_trackpad")
				if input_mode == int(AppSettingsStore.InputMode.TRACKPAD)
				else NotLightL10n.text("board.hint.hand_mouse")
			)
	_layout_tool_hint()


func _open_rename_dialog() -> void:
	if session == null:
		return
	_rename_dialog.open_dialog(
		NotLightL10n.text("hub.board.rename_title"),
		NotLightL10n.text("runtime.ui.board_screen.411db88b78"),
		str(session.metadata.get("name", "")),
		NotLightL10n.text("common.save")
	)


func _open_settings_dialog() -> void:
	_settings_dialog.open_dialog()


func _rename_current_board(clean_name: String) -> void:
	if session != null:
		session.rename_current_board(clean_name)


func _show_error(message: String) -> void:
	if message.is_empty():
		return
	_error_label.text = message
	_error_panel.visible = true
	_error_timer.start()


func _change_selected_formula_mode(mode: int) -> void:
	var entity_id: int = _selected_formula_id()
	if session == null or entity_id <= 0:
		return
	var before: Dictionary = session.runtime.model.formulas.get_record(entity_id)
	var after: Dictionary = before.duplicate(true)
	after["display_mode"] = FormulaStore.normalize_display_mode(mode)
	if FormulaRenderService.normalize_record(before) == FormulaRenderService.normalize_record(after):
		return
	session.execute_command(UpdateFormulaCommand.new(entity_id, before, after))


func _change_selected_formula_color(color: Color) -> void:
	var entity_id: int = _selected_formula_id()
	if session == null or entity_id <= 0:
		return
	var before: Dictionary = session.runtime.model.formulas.get_record(entity_id)
	var after: Dictionary = before.duplicate(true)
	after["foreground"] = Color(color.r, color.g, color.b, 1.0)
	if FormulaRenderService.normalize_record(before) == FormulaRenderService.normalize_record(after):
		return
	session.execute_command(UpdateFormulaCommand.new(entity_id, before, after))


func _copy_selected_formula_latex() -> void:
	var entity_id: int = _selected_formula_id()
	if session == null or entity_id <= 0:
		return
	DisplayServer.clipboard_set(session.runtime.model.formulas.get_source(entity_id))


func _on_formula_editor_visibility_changed(active: bool) -> void:
	_close_color_popover()
	if active:
		_set_library_drawer_open(false)
	if _library_button != null:
		_library_button.disabled = active
		_library_button.tooltip_text = (
			NotLightL10n.text("formula.editor.library_locked")
			if active
			else NotLightL10n.text("board.library.tooltip")
		)
	_refresh_context_toolbars()
	_update_hint_text()


func _build_formula_editor_panel() -> void:
	_formula_editor = FormulaEditorPanel.new()
	_formula_editor.name = "FormulaEditorPanel"
	_formula_editor.apply_requested.connect(_on_formula_editor_apply)
	_formula_editor.canceled.connect(_on_formula_editor_canceled)
	_formula_editor.color_picker_requested.connect(_open_formula_editor_color_popover)
	_formula_editor.editor_visibility_changed.connect(_on_formula_editor_visibility_changed)
	add_child(_formula_editor)


func _on_formula_create_requested(world_position: Vector2) -> void:
	if session == null or _formula_editor == null:
		return
	_formula_edit_entity_id = 0
	_formula_new_world_position = world_position
	_formula_editor.open_editor({
		"source_latex": "",
		"display_mode": FormulaStore.DEFAULT_DISPLAY_MODE,
		"font_scale": FormulaStore.DEFAULT_FONT_SCALE,
		"foreground": FormulaStore.DEFAULT_FOREGROUND,
	}, true)


func _on_formula_edit_requested(entity_id: int) -> void:
	if session == null or _formula_editor == null or not session.runtime.model.formulas.contains(entity_id):
		return
	_formula_edit_entity_id = entity_id
	_formula_new_world_position = Vector2.ZERO
	_formula_editor.open_editor(session.runtime.model.formulas.get_record(entity_id), false)


func _on_formula_editor_apply(record: Dictionary) -> void:
	if session == null or _formula_editor == null:
		return
	var normalized: Dictionary = FormulaRenderService.normalize_record(record)
	if str(normalized.get("source_latex", "")).strip_edges().is_empty():
		return
	if _formula_edit_entity_id > 0:
		var entity_id: int = _formula_edit_entity_id
		if not session.runtime.model.formulas.contains(entity_id):
			_discard_formula_draft()
			return
		var before_stored: Dictionary = session.runtime.model.formulas.get_record(entity_id)
		var before_normalized: Dictionary = FormulaRenderService.normalize_record(before_stored)
		if before_normalized != normalized:
			var update_command: UpdateFormulaCommand = UpdateFormulaCommand.new(entity_id, before_stored, normalized)
			if not session.execute_command(update_command):
				_show_error(NotLightL10n.text("formula.error.update_failed"))
				return
		_formula_editor.close_editor()
		_formula_edit_entity_id = 0
		_mark_board_search_snapshot_dirty()
		return
	var bounds: Rect2 = _recommended_formula_bounds(normalized, _formula_new_world_position)
	var z_order: int = session.runtime.model.get_max_z_order() + 1
	var foreground_value: Variant = normalized.get("foreground", FormulaStore.DEFAULT_FOREGROUND)
	var foreground: Color = foreground_value if foreground_value is Color else FormulaStore.DEFAULT_FOREGROUND
	var create_command: CreateFormulaCommand = CreateFormulaCommand.new(
		bounds,
		str(normalized.get("source_latex", "")),
		int(normalized.get("display_mode", FormulaStore.DEFAULT_DISPLAY_MODE)),
		float(normalized.get("font_scale", FormulaStore.DEFAULT_FONT_SCALE)),
		foreground,
		z_order
	)
	if not session.execute_command(create_command):
		_show_error(NotLightL10n.text("formula.error.create_failed"))
		return
	_formula_editor.close_editor()
	_formula_edit_entity_id = 0
	if create_command.created_entity_id > 0:
		session.runtime.selection.set_single(create_command.created_entity_id)
	# Creation is a one-shot placement action. Returning to selection prevents an
	# accidental second FormulaObject on the next board click and matches image/PDF
	# placement expectations.
	_set_active_tool(BoardToolController.TOOL_SELECT)
	_mark_board_search_snapshot_dirty()


func _on_formula_editor_canceled() -> void:
	_formula_edit_entity_id = 0
	_formula_new_world_position = Vector2.ZERO


func _discard_formula_draft() -> void:
	if _formula_editor != null and _formula_editor.visible:
		_formula_editor.close_editor()
	_formula_edit_entity_id = 0
	_formula_new_world_position = Vector2.ZERO


func _recommended_formula_bounds(record: Dictionary, center: Vector2) -> Rect2:
	var default_size: Vector2 = Vector2(300.0, 104.0)
	if int(record.get("display_mode", FormulaStore.DEFAULT_DISPLAY_MODE)) == FormulaStore.DISPLAY_INLINE:
		default_size = Vector2(250.0, 76.0)
	if formula_render != null:
		var texture: Texture2D = formula_render.get_cached_texture(record, 512.0)
		if texture != null:
			var source: Vector2 = texture.get_size()
			if source.x > 0.0 and source.y > 0.0:
				var width: float = clampf(source.x * 0.48, 180.0, 520.0)
				var height: float = clampf(width * source.y / source.x, 52.0, 260.0)
				default_size = Vector2(width, height) + Vector2(18.0, 18.0)
	return Rect2(center - default_size * 0.5, default_size)
