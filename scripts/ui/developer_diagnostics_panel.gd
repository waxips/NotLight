# SPDX-License-Identifier: GPL-3.0-or-later
class_name DeveloperDiagnosticsPanel
extends VBoxContainer

signal visibility_layout_changed

const MINIMUM_PANEL_WIDTH: float = 700.0

var settings: AppSettingsStore
var telemetry: PerformanceTelemetryService
var _title_label: Label
var _frame_label: Label
var _engine_label: Label
var _camera_label: Label
var _objects_label: Label
var _visibility_label: Label
var _scheduler_label: Label
var _scheduler_types_label: Label
var _stroke_label: Label
var _stroke_prepare_label: Label
var _connector_label: Label
var _pipeline_label: Label
var _audio_pipeline_label: Label
var _context_label: Label
var _context_events_label: Label
var _status_label: Label
var _save_button: Button
var _record_button: Button
var _folder_button: Button
var _last_sample: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_theme_constant_override("separation", 3)
	_build_ui()
	NotLightL10n.connect_locale_changed(_on_locale_changed)
	_refresh_visibility()


func _exit_tree() -> void:
	_disconnect_sources()
	NotLightL10n.disconnect_locale_changed(_on_locale_changed)


func configure(settings_store: AppSettingsStore, telemetry_service: PerformanceTelemetryService) -> void:
	_disconnect_sources()
	settings = settings_store
	telemetry = telemetry_service
	if settings != null and not settings.settings_changed.is_connected(_on_settings_changed):
		settings.settings_changed.connect(_on_settings_changed)
	if telemetry != null:
		if not telemetry.sample_updated.is_connected(_on_sample_updated):
			telemetry.sample_updated.connect(_on_sample_updated)
		if not telemetry.developer_recording_state_changed.is_connected(_on_recording_state_changed):
			telemetry.developer_recording_state_changed.connect(_on_recording_state_changed)
		if not telemetry.developer_diagnostics_error.is_connected(_on_diagnostics_error):
			telemetry.developer_diagnostics_error.connect(_on_diagnostics_error)
	_refresh_visibility()
	_on_sample_updated(telemetry.snapshot() if telemetry != null else {})
	_update_record_button()


func _disconnect_sources() -> void:
	if settings != null and settings.settings_changed.is_connected(_on_settings_changed):
		settings.settings_changed.disconnect(_on_settings_changed)
	if telemetry != null:
		if telemetry.sample_updated.is_connected(_on_sample_updated):
			telemetry.sample_updated.disconnect(_on_sample_updated)
		if telemetry.developer_recording_state_changed.is_connected(_on_recording_state_changed):
			telemetry.developer_recording_state_changed.disconnect(_on_recording_state_changed)
		if telemetry.developer_diagnostics_error.is_connected(_on_diagnostics_error):
			telemetry.developer_diagnostics_error.disconnect(_on_diagnostics_error)


func _build_ui() -> void:
	_title_label = Label.new()
	_title_label.theme_type_variation = "EyebrowLabel"
	add_child(_title_label)

	_frame_label = _make_line_label()
	_engine_label = _make_line_label()
	_camera_label = _make_line_label()
	_objects_label = _make_line_label()
	_visibility_label = _make_line_label()
	_scheduler_label = _make_line_label()
	_scheduler_types_label = _make_line_label()
	_stroke_label = _make_line_label()
	_stroke_prepare_label = _make_line_label()
	_connector_label = _make_line_label()
	_pipeline_label = _make_line_label()
	_audio_pipeline_label = _make_line_label()
	_context_label = _make_line_label()
	_context_events_label = _make_line_label()
	add_child(_frame_label)
	add_child(_engine_label)
	add_child(_camera_label)
	add_child(_objects_label)
	add_child(_visibility_label)
	add_child(_scheduler_label)
	add_child(_scheduler_types_label)
	add_child(_stroke_label)
	add_child(_stroke_prepare_label)
	add_child(_connector_label)
	add_child(_pipeline_label)
	add_child(_audio_pipeline_label)
	add_child(_context_label)
	add_child(_context_events_label)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	add_child(actions)
	_save_button = Button.new()
	_save_button.theme_type_variation = "GhostButton"
	_save_button.custom_minimum_size = Vector2(148.0, 32.0)
	_save_button.pressed.connect(_save_report)
	actions.add_child(_save_button)
	_record_button = Button.new()
	_record_button.theme_type_variation = "GhostButton"
	_record_button.custom_minimum_size = Vector2(176.0, 32.0)
	_record_button.pressed.connect(_toggle_recording)
	actions.add_child(_record_button)
	_folder_button = Button.new()
	_folder_button.theme_type_variation = "GhostButton"
	_folder_button.custom_minimum_size = Vector2(124.0, 32.0)
	_folder_button.pressed.connect(_open_folder)
	actions.add_child(_folder_button)

	_status_label = Label.new()
	_status_label.theme_type_variation = "CaptionLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(MINIMUM_PANEL_WIDTH, 0.0)
	_status_label.visible = false
	add_child(_status_label)
	_refresh_text()


func _make_line_label() -> Label:
	var label: Label = Label.new()
	label.theme_type_variation = "CaptionLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(MINIMUM_PANEL_WIDTH, 0.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _on_settings_changed(_snapshot: Dictionary) -> void:
	_refresh_visibility()


func _on_locale_changed(_locale: String) -> void:
	_refresh_text()
	_update_record_button()


func _refresh_visibility() -> void:
	var next_visible: bool = settings != null and settings.developer_diagnostics_enabled
	if visible == next_visible:
		return
	visible = next_visible
	visibility_layout_changed.emit()


func _on_sample_updated(sample: Dictionary) -> void:
	_last_sample = sample.duplicate(false)
	if visible:
		_refresh_text()
		_update_record_status()


func _on_recording_state_changed(_active: bool, path: String) -> void:
	_update_record_button()
	if not path.is_empty():
		_set_status(NotLightL10n.text("developer.diagnostics.saved_path", {"path": path}))


func _on_diagnostics_error(message: String) -> void:
	_set_status(message)


func _refresh_text() -> void:
	if _title_label == null:
		return
	NotLightL10n.bind_text(_title_label, "developer.diagnostics.title")
	_frame_label.text = NotLightL10n.text("developer.diagnostics.frame_line_v4", {
		"fps": int(round(float(_last_sample.get("fps", 0.0)))),
		"delta_avg": "%.1f" % float(_last_sample.get("dev_frame_delta_avg_ms", 0.0)),
		"delta_max": "%.1f" % float(_last_sample.get("dev_frame_delta_max_ms", 0.0)),
		"hitch_33": _format_rate(float(_last_sample.get("dev_hitch_33ms_per_second", 0.0))),
		"hitch_50": _format_rate(float(_last_sample.get("dev_hitch_50ms_per_second", 0.0))),
		"hitch_100": _format_rate(float(_last_sample.get("dev_hitch_100ms_per_second", 0.0))),
		"session_max": "%.1f" % float(_last_sample.get("dev_session_frame_delta_max_ms", 0.0)),
	})
	_engine_label.text = NotLightL10n.text("developer.diagnostics.engine_line", {
		"frame_ms": "%.1f" % float(_last_sample.get("frame_ms", 0.0)),
		"process_ms": "%.2f" % float(_last_sample.get("process_ms", 0.0)),
		"physics_ms": "%.2f" % float(_last_sample.get("physics_process_ms", 0.0)),
		"session_seconds": "%.1f" % float(_last_sample.get("dev_session_elapsed_seconds", 0.0)),
	})
	_camera_label.text = NotLightL10n.text("developer.diagnostics.camera_line_v2", {
		"camera": _camera_state_text(bool(_last_sample.get("dev_camera_moving", false))),
		"zoom": int(round(float(_last_sample.get("dev_zoom_percent", 100.0)))),
		"target_zoom": int(round(float(_last_sample.get("dev_target_zoom_percent", _last_sample.get("dev_zoom_percent", 100.0))))),
		"delta_px": "%.2f" % float(_last_sample.get("dev_camera_target_delta_px", 0.0)),
		"idle_ms": int(round(float(_last_sample.get("dev_camera_input_idle_ms", 0.0)))),
		"lod": str(_last_sample.get("dev_lod", "FULL")),
		"stroke_lod": str(_last_sample.get("dev_stroke_lod", "FULL")),
	})
	var object_total: int = int(_last_sample.get("dev_objects_total", 0))
	var object_text: int = int(_last_sample.get("dev_objects_text", 0))
	var object_images: int = int(_last_sample.get("dev_objects_images", 0))
	var object_videos: int = int(_last_sample.get("dev_objects_videos", 0))
	var object_audios: int = int(_last_sample.get("dev_objects_audios", 0))
	var object_strokes: int = int(_last_sample.get("dev_objects_strokes", 0))
	var object_connectors: int = int(_last_sample.get("dev_objects_connectors", 0))
	var object_other: int = maxi(0, object_total - object_text - object_images - object_videos - object_audios - object_strokes - object_connectors)
	_objects_label.text = NotLightL10n.text("developer.diagnostics.objects_line", {
		"total": _format_count(object_total),
		"text": _format_count(object_text),
		"images": _format_count(object_images),
		"videos": _format_count(object_videos),
		"audios": _format_count(object_audios),
		"strokes": _format_count(object_strokes),
		"connectors": _format_count(object_connectors),
		"other": _format_count(object_other),
		"index": _format_count(int(_last_sample.get("dev_spatial_index_size", 0))),
	})
	_visibility_label.text = NotLightL10n.text("developer.diagnostics.visibility_line_v2", {
		"total": _format_count(int(_last_sample.get("dev_visible_candidates_total", _last_sample.get("dev_visible_candidates", 0)))),
		"text": _format_count(int(_last_sample.get("dev_visible_text_candidates", 0))),
		"images": _format_count(int(_last_sample.get("dev_visible_image_candidates", 0))),
		"videos": _format_count(int(_last_sample.get("dev_visible_video_candidates", 0))),
		"audios": _format_count(int(_last_sample.get("dev_visible_audio_candidates", 0))),
		"strokes": _format_count(int(_last_sample.get("dev_visible_stroke_candidates", 0))),
		"connectors": _format_count(int(_last_sample.get("dev_visible_connector_candidates", 0))),
		"shared_coverage": "%.1f" % float(_last_sample.get("dev_shared_coverage_ratio", 0.0)),
		"stroke_coverage": "%.1f" % float(_last_sample.get("dev_stroke_coverage_ratio", 0.0)),
		"pending": int(_last_sample.get("dev_render_pending_mask", 0)),
		"deferred": _yes_no(bool(_last_sample.get("dev_view_refresh_deferred", false))),
	})
	_scheduler_label.text = NotLightL10n.text("developer.diagnostics.scheduler_line", {
		"rate": _format_rate(float(_last_sample.get("dev_rebuilds_per_second", 0.0))),
		"avg": "%.2f" % float(_last_sample.get("dev_rebuild_time_avg_ms", 0.0)),
		"max": "%.2f" % float(_last_sample.get("dev_rebuild_time_max_ms", 0.0)),
		"spatial": _format_rate(float(_last_sample.get("dev_spatial_queries_per_second", 0.0))),
		"spatial_max": "%.2f" % float(_last_sample.get("dev_spatial_query_max_ms", 0.0)),
		"commits": _format_rate(float(_last_sample.get("dev_view_refresh_commits_per_second", 0.0))),
		"deferrals": _format_rate(float(_last_sample.get("dev_render_motion_deferrals_per_second", 0.0))),
		"drops": _format_rate(float(_last_sample.get("dev_render_stale_view_drops_per_second", 0.0))),
		"budget_hits": _format_rate(float(_last_sample.get("dev_render_budget_hits_per_second", 0.0))),
	})
	_scheduler_types_label.text = NotLightL10n.text("developer.diagnostics.scheduler_types_line", {
		"text": "%.2f" % float(_last_sample.get("dev_rebuild_text_max_ms", 0.0)),
		"image": "%.2f" % float(_last_sample.get("dev_rebuild_image_max_ms", 0.0)),
		"video": "%.2f" % float(_last_sample.get("dev_rebuild_video_max_ms", 0.0)),
		"audio": "%.2f" % float(_last_sample.get("dev_rebuild_audio_max_ms", 0.0)),
		"connector": "%.2f" % float(_last_sample.get("dev_rebuild_connector_max_ms", 0.0)),
		"stroke": "%.2f" % float(_last_sample.get("dev_rebuild_stroke_max_ms", 0.0)),
		"stroke_session": "%.2f" % float(_last_sample.get("dev_session_rebuild_stroke_max_ms", 0.0)),
		"filter": "%.2f" % float(_last_sample.get("dev_candidate_filter_max_ms", 0.0)),
	})
	_stroke_label.text = NotLightL10n.text("developer.diagnostics.stroke_line_v4", {
		"rendered": _format_count(int(round(float(_last_sample.get("dev_stroke_rendered", 0.0))))),
		"candidates": _format_count(int(round(float(_last_sample.get("dev_stroke_candidates", _last_sample.get("dev_visible_stroke_candidates", 0)))))),
		"source_points": _format_count(int(round(float(_last_sample.get("dev_stroke_source_points", 0.0))))),
		"render_points": _format_count(int(round(float(_last_sample.get("dev_stroke_render_points", 0.0))))),
		"segments": _format_count(int(round(float(_last_sample.get("dev_stroke_segments", 0.0))))),
		"target_segments": _format_count(int(round(float(_last_sample.get("dev_stroke_target_segments", 0.0))))),
		"skipped": _format_count(int(round(float(_last_sample.get("dev_stroke_budget_skipped", 0.0))))),
		"stroke_avg": "%.2f" % float(_last_sample.get("dev_stroke_draw_avg_ms", 0.0)),
		"stroke_max": "%.2f" % float(_last_sample.get("dev_stroke_draw_max_ms", 0.0)),
	})
	_stroke_prepare_label.text = NotLightL10n.text("developer.diagnostics.stroke_prepare_line", {
		"requested_lod": _lod_name(int(round(float(_last_sample.get("dev_stroke_requested_lod", 0.0))))),
		"effective_lod": _lod_name(int(round(float(_last_sample.get("dev_stroke_effective_lod", 0.0))))),
		"point_limit": int(round(float(_last_sample.get("dev_stroke_adaptive_point_limit", 0.0)))),
		"cache_hits": _format_rate(float(_last_sample.get("dev_stroke_simplify_cache_hits_per_second", 0.0))),
		"cache_misses": _format_rate(float(_last_sample.get("dev_stroke_simplify_cache_misses_per_second", 0.0))),
		"simplify_avg": "%.2f" % float(_last_sample.get("dev_stroke_simplify_avg_ms", 0.0)),
		"simplify_max": "%.2f" % float(_last_sample.get("dev_stroke_simplify_max_ms", 0.0)),
		"draw_session": "%.2f" % float(_last_sample.get("dev_session_stroke_draw_max_ms", 0.0)),
	})
	_connector_label.text = NotLightL10n.text("developer.diagnostics.connector_line", {
		"rendered": _format_count(int(round(float(_last_sample.get("dev_connector_rendered", 0.0))))),
		"candidates": _format_count(int(round(float(_last_sample.get("dev_connector_candidates", _last_sample.get("dev_visible_connector_candidates", 0)))))),
		"segments": _format_count(int(round(float(_last_sample.get("dev_connector_segments", 0.0))))),
		"skipped": _format_count(int(round(float(_last_sample.get("dev_connector_budget_skipped", 0.0))))),
		"connector_avg": "%.2f" % float(_last_sample.get("dev_connector_draw_avg_ms", 0.0)),
		"connector_max": "%.2f" % float(_last_sample.get("dev_connector_draw_max_ms", 0.0)),
	})
	_pipeline_label.text = NotLightL10n.text("developer.diagnostics.pipeline_line_v3", {
		"text_submit": _format_rate(float(_last_sample.get("dev_text_submits_per_second", 0.0))),
		"text_apply": _format_rate(float(_last_sample.get("dev_text_applies_per_second", 0.0))),
		"image_requests": _format_rate(float(_last_sample.get("dev_image_requests_per_second", 0.0))),
		"image_uploads": _format_rate(float(_last_sample.get("dev_image_uploads_per_second", 0.0))),
		"text_apply_max": "%.2f" % float(_last_sample.get("dev_text_apply_max_ms", 0.0)),
	})
	_audio_pipeline_label.text = NotLightL10n.text("developer.diagnostics.audio_pipeline_line", {
		"players": int(_last_sample.get("dev_audio_players_active", 0)),
		"prepare": int(_last_sample.get("dev_audio_prepare_queue", 0)),
		"waveform": int(_last_sample.get("dev_audio_waveform_load_queue", 0)),
		"cache": int(_last_sample.get("dev_audio_waveform_cache", 0)),
		"stage": _audio_stage_name(int(_last_sample.get("dev_audio_active_stage", 0))),
		"ffmpeg": _tool_state_name(int(_last_sample.get("dev_audio_ffmpeg_state", -1))),
		"voice": _yes_no(bool(_last_sample.get("dev_voice_recording_active", false))),
		"voice_jobs": int(_last_sample.get("dev_voice_pending_jobs", 0)),
	})
	_context_label.text = NotLightL10n.text("developer.diagnostics.context_line_v2", {
		"selection": int(_last_sample.get("dev_selection_count", 0)),
		"primary_type": str(_last_sample.get("dev_selection_primary_type", "-")),
		"suppressed": _yes_no(bool(_last_sample.get("dev_context_ui_suppressed", false))),
		"requested": _yes_no(bool(_last_sample.get("dev_context_anchor_requested", false))),
		"native_visible": _yes_no(bool(_last_sample.get("dev_context_anchor_visible", false))),
		"dirty": _yes_no(bool(_last_sample.get("dev_context_anchor_dirty", false))),
		"toolbars": int(_last_sample.get("dev_context_visible_toolbars", 0)),
	})
	_context_events_label.text = NotLightL10n.text("developer.diagnostics.context_events_line", {
		"hides": _format_rate(float(_last_sample.get("dev_context_hides_per_second", 0.0))),
		"restores": _format_rate(float(_last_sample.get("dev_context_restores_per_second", 0.0))),
		"hud_refresh": _format_rate(float(_last_sample.get("dev_context_refreshes_per_second", 0.0))),
		"hud_move": _format_rate(float(_last_sample.get("dev_context_repositions_per_second", 0.0))),
		"profile": str(_last_sample.get("dev_performance_profile", "AUTO")),
	})
	if _save_button != null:
		NotLightL10n.bind_text(_save_button, "developer.diagnostics.save_report")
		NotLightL10n.bind_tooltip(_save_button, "developer.diagnostics.save_report_help")
	if _folder_button != null:
		NotLightL10n.bind_text(_folder_button, "developer.diagnostics.open_folder")
		NotLightL10n.bind_tooltip(_folder_button, "developer.diagnostics.open_folder_help")
	if _record_button != null:
		NotLightL10n.bind_tooltip(_record_button, "developer.diagnostics.record_help")


func _save_report() -> void:
	if telemetry == null:
		return
	var path: String = telemetry.save_developer_report()
	if not path.is_empty():
		_set_status(NotLightL10n.text("developer.diagnostics.saved_path", {"path": path}))


func _toggle_recording() -> void:
	if telemetry == null:
		return
	var path: String = ""
	if telemetry.is_developer_recording():
		path = telemetry.stop_developer_recording()
	else:
		path = telemetry.start_developer_recording()
	if not path.is_empty():
		_set_status(NotLightL10n.text("developer.diagnostics.saved_path", {"path": path}))
	_update_record_button()


func _open_folder() -> void:
	if telemetry == null:
		return
	var path: String = telemetry.prepare_diagnostics_folder()
	if not path.is_empty():
		OS.shell_show_in_file_manager(path, true)


func _update_record_button() -> void:
	if _record_button == null:
		return
	var recording: bool = telemetry != null and telemetry.is_developer_recording()
	_record_button.text = NotLightL10n.text(
		"developer.diagnostics.stop_recording" if recording else "developer.diagnostics.start_recording"
	)


func _update_record_status() -> void:
	if telemetry == null or not telemetry.is_developer_recording():
		return
	_set_status(NotLightL10n.text("developer.diagnostics.recording_status", {
		"seconds": "%.1f" % telemetry.developer_recording_elapsed_seconds(),
	}))


func _set_status(message: String) -> void:
	if _status_label == null:
		return
	var was_visible: bool = _status_label.visible
	_status_label.text = message
	_status_label.tooltip_text = message
	_status_label.visible = not message.is_empty()
	# Recording updates the elapsed time several times per second. The text can be
	# refreshed without asking BoardScreen to recompute the entire bottom layout.
	if was_visible != _status_label.visible:
		visibility_layout_changed.emit()


func _audio_stage_name(stage: int) -> String:
	match stage:
		1:
			return NotLightL10n.text("developer.diagnostics.stage.transcode")
		2:
			return NotLightL10n.text("developer.diagnostics.stage.waveform")
		_:
			return NotLightL10n.text("developer.diagnostics.stage.idle")


func _tool_state_name(state: int) -> String:
	match state:
		0:
			return NotLightL10n.text("common.no")
		1:
			return NotLightL10n.text("common.yes")
		_:
			return NotLightL10n.text("developer.diagnostics.tool_state.unchecked")


func _lod_name(lod_level: int) -> String:
	match lod_level:
		1:
			return NotLightL10n.text("developer.diagnostics.lod.medium")
		2:
			return NotLightL10n.text("developer.diagnostics.lod.low")
		3:
			return NotLightL10n.text("developer.diagnostics.lod.placeholder")
		_:
			return NotLightL10n.text("developer.diagnostics.lod.full")


func _camera_state_text(moving: bool) -> String:
	return NotLightL10n.text("developer.diagnostics.camera_moving" if moving else "developer.diagnostics.camera_idle")


func _yes_no(value: bool) -> String:
	return NotLightL10n.text("common.yes" if value else "common.no")


func _format_rate(value: float) -> String:
	if value >= 100.0:
		return NotLightL10n.text("ui.format.rate_zero_decimals") % value
	if value >= 10.0:
		return "%.1f" % value
	return NotLightL10n.text("ui.format.rate_two_decimals") % value


func _format_count(value: int) -> String:
	var clean: int = maxi(0, value)
	if clean >= 1000000:
		return NotLightL10n.text("ui.format.count_million") % (float(clean) / 1000000.0)
	if clean >= 1000:
		return NotLightL10n.text("ui.format.count_thousand") % (float(clean) / 1000.0)
	return str(clean)
