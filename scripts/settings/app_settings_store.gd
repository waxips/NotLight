# SPDX-License-Identifier: GPL-3.0-or-later
class_name AppSettingsStore
extends Node

enum InputMode {
	TRACKPAD,
	MOUSE,
}

enum CompressionCpuMode {
	ECO,
	BALANCED,
	MAXIMUM,
}

enum WindowModePreference {
	WINDOWED,
	MAXIMIZED,
	FULLSCREEN,
}

enum PerformanceProfile {
	AUTO,
	ECO,
	BALANCED,
	PERFORMANCE,
	CUSTOM,
}

enum DrawingQuality {
	ECO,
	BALANCED,
	HIGH,
	ULTRA,
}

enum GridIntensity {
	SOFT,
	BALANCED,
	EXPRESSIVE,
}

signal settings_changed(settings: Dictionary)
signal settings_error(message: String)

const SETTINGS_PATH: String = "user://notlight/settings.json"
const SETTINGS_SCHEMA_VERSION: int = 18
const DEFAULT_CAMERA_SENSITIVITY: float = 1.0
const DEFAULT_ZOOM_SENSITIVITY: float = 1.0
const DEFAULT_CAMERA_SPEED: float = 9.5
const SAVE_DEBOUNCE_SECONDS: float = 0.35
const INTERACTIVE_BROADCAST_DEBOUNCE_SECONDS: float = 0.08
const DEFAULT_LIBRARY_ROOT: String = "user://notlight/library"
const DEFAULT_MODULE_ROOT: String = "user://notlight/modules"
const DEFAULT_LOCALE: String = "ru"
const DEFAULT_AUDIO_MASTER_VOLUME: float = 1.0
const DEFAULT_BACKGROUND_MUSIC_VOLUME: float = 0.32
const BACKGROUND_MUSIC_ROOT: String = "res://assets/audio/background"
const MAX_USER_PALETTE_PRESETS: int = 32
const MAX_USER_PALETTE_NAME_LENGTH: int = 48
const MAX_DRAWING_PRESETS: int = 16
const MAX_DRAWING_PRESET_NAME_LENGTH: int = 40

const MICROPHONE_CONSENT_UNKNOWN: int = 0
const MICROPHONE_CONSENT_ALLOWED: int = 1
const MICROPHONE_CONSENT_DECLINED: int = 2

const MIN_BOARD_OBJECT_BUDGET: int = 500
const MAX_BOARD_OBJECT_BUDGET: int = 250000
const MIN_MATERIALIZED_UI_BUDGET: int = 16
const MAX_MATERIALIZED_UI_BUDGET: int = 2048
const MIN_VIDEO_PLAYERS: int = 1
const MAX_VIDEO_PLAYERS: int = 64
const MIN_MODULE_SURFACES: int = 1
const MAX_MODULE_SURFACES: int = 32
const MIN_NOTE_WORKSPACE_SURFACES: int = 1
const MAX_NOTE_WORKSPACE_SURFACES: int = 32
const DEFAULT_NOTE_WORKSPACE_SURFACES: int = 3
const MIN_NOTE_EMBED_LIVE_MEDIA: int = 1
const MAX_NOTE_EMBED_LIVE_MEDIA: int = 64
const DEFAULT_NOTE_EMBED_LIVE_MEDIA: int = 2
const MIN_TEXTURE_CACHE_MB: int = 128
const MAX_TEXTURE_CACHE_MB: int = 16384

var input_mode: InputMode = InputMode.TRACKPAD
var camera_sensitivity: float = DEFAULT_CAMERA_SENSITIVITY
var zoom_sensitivity: float = DEFAULT_ZOOM_SENSITIVITY
var camera_speed: float = DEFAULT_CAMERA_SPEED

var locale: String = DEFAULT_LOCALE
var window_mode: WindowModePreference = WindowModePreference.MAXIMIZED
var palette_id: String = NotLightPalette.PRESET_DEFAULT
var custom_palette: Dictionary = NotLightPalette.default_palette()
var grid_intensity: GridIntensity = GridIntensity.BALANCED
var user_palette_presets: Dictionary = {}

var drawing_style: int = StrokeStore.STYLE_PEN
var drawing_color: Color = Color("#245cff")
var drawing_width: float = 4.0
var drawing_eraser_radius: float = 18.0
var drawing_spray_spread: float = 1.0
var user_drawing_presets: Dictionary = {}

var show_fps: bool = true
var show_ram: bool = false
var show_cpu: bool = false
var show_gpu: bool = false
var show_vram: bool = false
var show_battery: bool = false
var show_tool_hints: bool = true
var monitor_interval_seconds: float = 1.0
var developer_diagnostics_enabled: bool = false
var prefer_maximum_fps: bool = false
# First-use privacy consent for voice notes. This is an application preference,
# not a substitute for the operating system microphone permission.
# 0 = not asked, 1 = allowed, 2 = declined.
var microphone_consent_state: int = MICROPHONE_CONSENT_UNKNOWN

var audio_master_enabled: bool = true
var audio_master_volume: float = DEFAULT_AUDIO_MASTER_VOLUME
var background_music_enabled: bool = false
var background_music_volume: float = DEFAULT_BACKGROUND_MUSIC_VOLUME
var background_music_track: String = ""
var background_music_asset_id: String = ""

var performance_profile: PerformanceProfile = PerformanceProfile.AUTO
var custom_board_object_budget: int = 12000
var custom_materialized_ui_budget: int = 96
var custom_active_video_players: int = 10
var custom_active_module_surfaces: int = 3
var custom_active_note_workspace_surfaces: int = DEFAULT_NOTE_WORKSPACE_SURFACES
var custom_full_note_card_render: bool = false
var custom_note_embed_live_media: int = DEFAULT_NOTE_EMBED_LIVE_MEDIA
var custom_note_embed_rich_preview: bool = true
var custom_texture_cache_mb: int = 512
var custom_drawing_quality: DrawingQuality = DrawingQuality.HIGH

var library_root: String = DEFAULT_LIBRARY_ROOT
var module_root: String = DEFAULT_MODULE_ROOT
var compression_cpu_mode: CompressionCpuMode = CompressionCpuMode.ECO
var auto_optimize_video: bool = false

var _last_error: String = ""
var _save_timer: Timer
var _interactive_broadcast_timer: Timer
var _pending_save: bool = false
var _pending_settings_broadcast: bool = false


func _ready() -> void:
	_ensure_save_timer()
	_ensure_interactive_broadcast_timer()


func setup() -> bool:
	_last_error = ""
	var parent_dir: String = SETTINGS_PATH.get_base_dir()
	if not _ensure_directory(parent_dir):
		return false
	if not FileAccess.file_exists(SETTINGS_PATH):
		reset_defaults(false)
		return save()
	var loaded: Dictionary = _read_json_with_backup(SETTINGS_PATH)
	if loaded.is_empty():
		reset_defaults(false)
		return save()
	var loaded_version: int = int(loaded.get("schema_version", 1))
	_apply_dictionary(_migrate_settings_dictionary(loaded))
	if loaded_version < SETTINGS_SCHEMA_VERSION and not save():
		return false
	settings_changed.emit(get_snapshot())
	return true


func get_last_error() -> String:
	return _last_error


func _migrate_settings_dictionary(source: Dictionary) -> Dictionary:
	var migrated: Dictionary = source.duplicate(true)
	var source_version: int = int(migrated.get("schema_version", 1))
	# v11 adds only a presentation preference. Old profiles intentionally preserve
	# every existing value and opt into the historical default (hints visible).
	if source_version < 11 and not migrated.has("show_tool_hints"):
		migrated["show_tool_hints"] = true
	# v12 adds the bounded live-module surface budget. Existing profiles inherit
	# the original Stage 10 behavior (three simultaneous live module surfaces).
	if source_version < 12 and not migrated.has("custom_active_module_surfaces"):
		migrated["custom_active_module_surfaces"] = 3
	# v13 makes the bounded live Notes workspace pool configurable. Existing
	# profiles inherit the Stage 11.3 product default: three live rich surfaces.
	if source_version < 13 and not migrated.has("custom_active_note_workspace_surfaces"):
		migrated["custom_active_note_workspace_surfaces"] = DEFAULT_NOTE_WORKSPACE_SURFACES
	# v14 fixes the Stage 11.3 frame-rate preference persistence and adds an
	# opt-in high-detail retained renderer for lightweight board notes.
	if source_version < 14:
		if not migrated.has("prefer_maximum_fps"):
			migrated["prefer_maximum_fps"] = false
		if not migrated.has("custom_full_note_card_render"):
			migrated["custom_full_note_card_render"] = false
	# v15 allows the trusted module package repository to live on a user-selected
	# volume. Existing installations keep the historical user:// location.
	if source_version < 15 and not migrated.has("module_root"):
		migrated["module_root"] = DEFAULT_MODULE_ROOT
	# v16 separates Notes media-embed presentation budgets from board media.
	# Existing profiles keep a conservative two live media decoders per Notes
	# workspace and opt into rich static previews.
	if source_version < 16:
		if not migrated.has("custom_note_embed_live_media"):
			migrated["custom_note_embed_live_media"] = DEFAULT_NOTE_EMBED_LIVE_MEDIA
		if not migrated.has("custom_note_embed_rich_preview"):
			migrated["custom_note_embed_rich_preview"] = true
	# v17 adds the application-wide audio master and optional bundled background
	# music. Existing installations keep media audible but do not start music
	# without an explicit opt-in.
	if source_version < 17:
		if not migrated.has("audio_master_enabled"):
			migrated["audio_master_enabled"] = true
		if not migrated.has("audio_master_volume"):
			migrated["audio_master_volume"] = DEFAULT_AUDIO_MASTER_VOLUME
		if not migrated.has("background_music_enabled"):
			migrated["background_music_enabled"] = false
		if not migrated.has("background_music_volume"):
			migrated["background_music_volume"] = DEFAULT_BACKGROUND_MUSIC_VOLUME
		if not migrated.has("background_music_track"):
			migrated["background_music_track"] = ""
	# v18 lets background music reference any audio item in the managed Resource
	# Library by stable asset_id. Bundled res:// tracks remain fully supported.
	if source_version < 18 and not migrated.has("background_music_asset_id"):
		migrated["background_music_asset_id"] = ""
	migrated["schema_version"] = SETTINGS_SCHEMA_VERSION
	return migrated


func get_snapshot() -> Dictionary:
	return {
		"schema": "notlight.settings",
		"schema_version": SETTINGS_SCHEMA_VERSION,
		"input_mode": int(input_mode),
		"camera_sensitivity": camera_sensitivity,
		"zoom_sensitivity": zoom_sensitivity,
		"camera_speed": camera_speed,
		"locale": locale,
		"window_mode": int(window_mode),
		"palette_id": palette_id,
		"custom_palette": custom_palette.duplicate(true),
		"grid_intensity": int(grid_intensity),
		"user_palette_presets": user_palette_presets.duplicate(true),
		"drawing_style": drawing_style,
		"drawing_color": drawing_color.to_html(true),
		"drawing_width": drawing_width,
		"drawing_eraser_radius": drawing_eraser_radius,
		"drawing_spray_spread": drawing_spray_spread,
		"user_drawing_presets": user_drawing_presets.duplicate(true),
		"show_fps": show_fps,
		"show_ram": show_ram,
		"show_cpu": show_cpu,
		"show_gpu": show_gpu,
		"show_vram": show_vram,
		"show_battery": show_battery,
		"show_tool_hints": show_tool_hints,
		"monitor_interval_seconds": monitor_interval_seconds,
		"developer_diagnostics_enabled": developer_diagnostics_enabled,
		"prefer_maximum_fps": prefer_maximum_fps,
		"microphone_consent_state": microphone_consent_state,
		"audio_master_enabled": audio_master_enabled,
		"audio_master_volume": audio_master_volume,
		"background_music_enabled": background_music_enabled,
		"background_music_volume": background_music_volume,
		"background_music_track": background_music_track,
		"background_music_asset_id": background_music_asset_id,
		"performance_profile": int(performance_profile),
		"custom_board_object_budget": custom_board_object_budget,
		"custom_materialized_ui_budget": custom_materialized_ui_budget,
		"custom_active_video_players": custom_active_video_players,
		"custom_active_module_surfaces": custom_active_module_surfaces,
		"custom_active_note_workspace_surfaces": custom_active_note_workspace_surfaces,
		"custom_full_note_card_render": custom_full_note_card_render,
		"custom_note_embed_live_media": custom_note_embed_live_media,
		"custom_note_embed_rich_preview": custom_note_embed_rich_preview,
		"effective_full_note_card_render": bool(get_performance_budget().get("full_note_card_render", false)),
		"effective_note_embed_live_media": int(get_performance_budget().get("note_embed_live_media", DEFAULT_NOTE_EMBED_LIVE_MEDIA)),
		"effective_note_embed_rich_preview": bool(get_performance_budget().get("note_embed_rich_preview", true)),
		"custom_texture_cache_mb": custom_texture_cache_mb,
		"custom_drawing_quality": int(custom_drawing_quality),
		"effective_drawing_quality": int(get_effective_drawing_quality()),
		"library_root": library_root,
		"module_root": module_root,
		"compression_cpu_mode": int(compression_cpu_mode),
		"auto_optimize_video": auto_optimize_video,
	}


func get_effective_palette() -> Dictionary:
	if user_palette_presets.has(palette_id):
		var record: Dictionary = user_palette_presets.get(palette_id, {}) as Dictionary
		var raw_colors: Variant = record.get("colors", {})
		if raw_colors is Dictionary:
			return NotLightPalette.sanitize_custom(raw_colors as Dictionary)
	return NotLightPalette.effective(palette_id, custom_palette)


func list_user_palette_presets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_id: Variant in user_palette_presets.keys():
		var preset_id: String = str(raw_id)
		var raw_record: Variant = user_palette_presets.get(preset_id, {})
		if raw_record is not Dictionary:
			continue
		var record: Dictionary = (raw_record as Dictionary).duplicate(true)
		record["id"] = preset_id
		result.append(record)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("name", "")).naturalnocasecmp_to(str(right.get("name", ""))) < 0
	)
	return result


func is_user_palette_preset(preset_id: String) -> bool:
	return user_palette_presets.has(preset_id.strip_edges())


func save_user_palette_preset(display_name: String) -> String:
	var clean_name: String = _sanitize_palette_preset_name(display_name)
	if clean_name.is_empty():
		return ""
	var existing_id: String = _find_user_palette_id_by_name(clean_name)
	var preset_id: String = existing_id if not existing_id.is_empty() else _make_user_palette_id(clean_name)
	if preset_id.is_empty():
		return ""
	if existing_id.is_empty() and user_palette_presets.size() >= MAX_USER_PALETTE_PRESETS:
		return ""
	var now: int = int(Time.get_unix_time_from_system())
	var previous: Dictionary = {}
	if user_palette_presets.has(preset_id) and user_palette_presets[preset_id] is Dictionary:
		previous = (user_palette_presets[preset_id] as Dictionary).duplicate(true)
	var colors: Dictionary = NotLightPalette.sanitize_custom(get_effective_palette())
	user_palette_presets[preset_id] = {
		"name": clean_name,
		"colors": colors,
		"created_at_unix": int(previous.get("created_at_unix", now)),
		"updated_at_unix": now,
	}
	custom_palette = colors.duplicate(true)
	palette_id = preset_id
	_commit_change()
	return preset_id


func delete_user_palette_preset(preset_id: String) -> bool:
	var clean_id: String = preset_id.strip_edges()
	if not user_palette_presets.has(clean_id):
		return false
	user_palette_presets.erase(clean_id)
	if palette_id == clean_id:
		palette_id = NotLightPalette.PRESET_DEFAULT
		custom_palette = NotLightPalette.default_palette()
	_commit_change()
	return true


func get_performance_budget() -> Dictionary:
	var profile: int = int(performance_profile)
	if profile == int(PerformanceProfile.AUTO):
		profile = _auto_profile()
	match profile:
		PerformanceProfile.ECO:
			return _budget(5000, 48, 4, 1, 1, 256, false, 1, false)
		PerformanceProfile.BALANCED:
			return _budget(12000, 96, 8, 3, 3, 512, false, 2, true)
		PerformanceProfile.PERFORMANCE:
			return _budget(30000, 160, 16, 8, 8, 1536, false, 16, true)
		PerformanceProfile.CUSTOM:
			return _budget(
				custom_board_object_budget,
				custom_materialized_ui_budget,
				custom_active_video_players,
				custom_active_module_surfaces,
				custom_active_note_workspace_surfaces,
				custom_texture_cache_mb,
				custom_full_note_card_render,
				custom_note_embed_live_media,
				custom_note_embed_rich_preview
			)
		_:
			return _budget(12000, 96, 8, 3, 3, 512, false, 2, true)


func get_effective_drawing_quality() -> DrawingQuality:
	var profile: int = int(performance_profile)
	if profile == int(PerformanceProfile.AUTO):
		profile = _auto_profile()
	match profile:
		PerformanceProfile.ECO:
			return DrawingQuality.ECO
		PerformanceProfile.BALANCED:
			return DrawingQuality.BALANCED
		PerformanceProfile.PERFORMANCE:
			return DrawingQuality.ULTRA
		PerformanceProfile.CUSTOM:
			return custom_drawing_quality
		_:
			return DrawingQuality.HIGH


func set_custom_drawing_quality(value: int) -> void:
	var clean: DrawingQuality = _drawing_quality_from_int(value)
	if custom_drawing_quality == clean and performance_profile == PerformanceProfile.CUSTOM:
		return
	custom_drawing_quality = clean
	performance_profile = PerformanceProfile.CUSTOM
	_commit_change()


func apply_render_policy(policy: BoardRenderPolicy) -> void:
	if policy == null:
		return
	var budget: Dictionary = get_performance_budget()
	var objects: int = int(budget.get("board_object_budget", 12000))
	policy.max_visible_text_blocks = objects
	policy.max_visible_text_previews = maxi(600, int(objects / 5))
	policy.max_visible_connectors = maxi(1200, int(objects / 3))
	policy.max_visible_connector_segments = maxi(24000, objects * 10)
	policy.max_visible_images = maxi(320, int(objects / 10))
	policy.max_visible_videos = maxi(80, int(objects / 40))
	policy.max_visible_audios = maxi(160, int(objects / 20))
	policy.max_visible_pdf_pages = maxi(100, int(objects / 30))
	policy.max_visible_formulas = maxi(300, int(objects / 8))
	policy.max_visible_note_portals = maxi(600, int(objects / 5))
	policy.max_visible_stroke_segments = maxi(40000, objects * 12)
	policy.max_rebuilds_per_frame = clampi(
		int(int(budget.get("materialized_ui_budget", 96)) / 8),
		4,
		256
	)
	policy.max_texture_memory_mb = int(budget.get("texture_cache_mb", 512))
	match get_effective_drawing_quality():
		DrawingQuality.ECO:
			policy.stroke_smoothing_steps = 2
			policy.stroke_input_spacing_scale = 1.35
			policy.spray_density = 0.48
			policy.max_spray_particles_per_stroke = 700
			policy.spray_preview_particles = 55
		DrawingQuality.BALANCED:
			policy.stroke_smoothing_steps = 3
			policy.stroke_input_spacing_scale = 1.0
			policy.spray_density = 0.72
			policy.max_spray_particles_per_stroke = 1200
			policy.spray_preview_particles = 80
		DrawingQuality.HIGH:
			policy.stroke_smoothing_steps = 4
			policy.stroke_input_spacing_scale = 0.78
			policy.spray_density = 0.95
			policy.max_spray_particles_per_stroke = 1900
			policy.spray_preview_particles = 110
		DrawingQuality.ULTRA:
			policy.stroke_smoothing_steps = 5
			policy.stroke_input_spacing_scale = 0.62
			policy.spray_density = 1.20
			policy.max_spray_particles_per_stroke = 3000
			policy.spray_preview_particles = 150


func set_input_mode(value: int) -> void:
	var normalized: InputMode = InputMode.TRACKPAD if value == int(InputMode.TRACKPAD) else InputMode.MOUSE
	if input_mode == normalized:
		return
	input_mode = normalized
	_commit_change()


func set_camera_sensitivity(value: float) -> void:
	var normalized: float = clampf(value, 0.25, 3.0)
	if is_equal_approx(camera_sensitivity, normalized):
		return
	camera_sensitivity = normalized
	_commit_change(true)


func set_zoom_sensitivity(value: float) -> void:
	var normalized: float = clampf(value, 0.25, 3.0)
	if is_equal_approx(zoom_sensitivity, normalized):
		return
	zoom_sensitivity = normalized
	_commit_change(true)


func set_camera_speed(value: float) -> void:
	var normalized: float = clampf(value, 3.0, 30.0)
	if is_equal_approx(camera_speed, normalized):
		return
	camera_speed = normalized
	_commit_change(true)


func set_locale(value: String) -> void:
	var normalized: String = value.strip_edges().to_lower()
	if not NotLightL10n.available_locales().has(normalized):
		normalized = DEFAULT_LOCALE
	if locale == normalized:
		return
	locale = normalized
	NotLightL10n.set_locale(locale)
	_commit_change()


func set_grid_intensity(value: int) -> void:
	var normalized: GridIntensity = GridIntensity.BALANCED
	if value == int(GridIntensity.SOFT):
		normalized = GridIntensity.SOFT
	elif value == int(GridIntensity.EXPRESSIVE):
		normalized = GridIntensity.EXPRESSIVE
	if grid_intensity == normalized:
		return
	grid_intensity = normalized
	_commit_change()


func set_window_mode(value: int) -> void:
	var normalized: WindowModePreference = WindowModePreference.WINDOWED
	if value == int(WindowModePreference.MAXIMIZED):
		normalized = WindowModePreference.MAXIMIZED
	elif value == int(WindowModePreference.FULLSCREEN):
		normalized = WindowModePreference.FULLSCREEN
	if window_mode == normalized:
		return
	window_mode = normalized
	_commit_change()


func set_palette_id(value: String) -> void:
	var normalized: String = value.strip_edges()
	if not _is_valid_palette_id(normalized):
		normalized = NotLightPalette.PRESET_DEFAULT
	if palette_id == normalized:
		return
	palette_id = normalized
	if user_palette_presets.has(palette_id):
		var record: Dictionary = user_palette_presets.get(palette_id, {}) as Dictionary
		var raw_colors: Variant = record.get("colors", {})
		if raw_colors is Dictionary:
			custom_palette = NotLightPalette.sanitize_custom(raw_colors as Dictionary)
	elif palette_id == NotLightPalette.PRESET_CUSTOM and custom_palette.is_empty():
		custom_palette = NotLightPalette.default_palette()
	_commit_change()


func set_custom_palette_color(key: String, color: Color) -> void:
	if not NotLightPalette.SEMANTIC_KEYS.has(key):
		return
	var next: Dictionary = custom_palette.duplicate(true)
	next[key] = color.to_html(false)
	custom_palette = NotLightPalette.sanitize_custom(next)
	palette_id = NotLightPalette.PRESET_CUSTOM
	_commit_change()


func reset_custom_palette() -> void:
	custom_palette = NotLightPalette.default_palette()
	palette_id = NotLightPalette.PRESET_CUSTOM
	_commit_change()


func set_show_fps(value: bool) -> void:
	_set_monitor_flag("fps", value)


func set_show_ram(value: bool) -> void:
	_set_monitor_flag("ram", value)


func set_show_cpu(value: bool) -> void:
	_set_monitor_flag("cpu", value)


func set_show_gpu(value: bool) -> void:
	_set_monitor_flag("gpu", value)


func set_show_vram(value: bool) -> void:
	_set_monitor_flag("vram", value)


func set_show_battery(value: bool) -> void:
	_set_monitor_flag("battery", value)


func set_show_tool_hints(value: bool) -> void:
	if show_tool_hints == value:
		return
	show_tool_hints = value
	_commit_change()


func set_monitor_interval(value: float) -> void:
	var normalized: float = clampf(value, 0.5, 5.0)
	if is_equal_approx(monitor_interval_seconds, normalized):
		return
	monitor_interval_seconds = normalized
	_commit_change()


func set_developer_diagnostics_enabled(value: bool) -> void:
	if developer_diagnostics_enabled == value:
		return
	developer_diagnostics_enabled = value
	_commit_change()


func set_prefer_maximum_fps(value: bool) -> void:
	if prefer_maximum_fps == value:
		return
	prefer_maximum_fps = value
	_commit_change()


func set_microphone_consent_state(value: int) -> void:
	var normalized: int = clampi(value, MICROPHONE_CONSENT_UNKNOWN, MICROPHONE_CONSENT_DECLINED)
	if microphone_consent_state == normalized:
		return
	microphone_consent_state = normalized
	_commit_change()


func set_audio_master_enabled(value: bool) -> void:
	if audio_master_enabled == value:
		return
	audio_master_enabled = value
	_commit_change()


func set_audio_master_volume(value: float) -> void:
	var normalized: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(audio_master_volume, normalized):
		return
	audio_master_volume = normalized
	_commit_change(true)


func set_background_music_enabled(value: bool) -> void:
	if background_music_enabled == value:
		return
	background_music_enabled = value
	_commit_change()


func set_background_music_volume(value: float) -> void:
	var normalized: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(background_music_volume, normalized):
		return
	background_music_volume = normalized
	_commit_change(true)


func set_background_music_track(value: String) -> void:
	var normalized: String = _sanitize_background_music_track(value)
	if background_music_track == normalized and background_music_asset_id.is_empty():
		return
	background_music_track = normalized
	background_music_asset_id = ""
	_commit_change()


func set_background_music_asset_id(value: String) -> void:
	var normalized: String = _sanitize_asset_id(value)
	if background_music_asset_id == normalized and background_music_track.is_empty():
		return
	background_music_asset_id = normalized
	background_music_track = ""
	_commit_change()


func clear_background_music_selection() -> void:
	if background_music_track.is_empty() and background_music_asset_id.is_empty():
		return
	background_music_track = ""
	background_music_asset_id = ""
	_commit_change()


func set_performance_profile(value: int) -> void:
	var normalized: PerformanceProfile = _performance_profile_from_int(value)
	if performance_profile == normalized:
		return
	performance_profile = normalized
	_commit_change()


func set_custom_board_object_budget(value: int) -> void:
	var normalized: int = clampi(value, MIN_BOARD_OBJECT_BUDGET, MAX_BOARD_OBJECT_BUDGET)
	if custom_board_object_budget == normalized:
		return
	custom_board_object_budget = normalized
	performance_profile = PerformanceProfile.CUSTOM
	_commit_change()


func set_custom_materialized_ui_budget(value: int) -> void:
	var normalized: int = clampi(value, MIN_MATERIALIZED_UI_BUDGET, MAX_MATERIALIZED_UI_BUDGET)
	if custom_materialized_ui_budget == normalized:
		return
	custom_materialized_ui_budget = normalized
	performance_profile = PerformanceProfile.CUSTOM
	_commit_change()


func set_custom_active_video_players(value: int) -> void:
	var normalized: int = clampi(value, MIN_VIDEO_PLAYERS, MAX_VIDEO_PLAYERS)
	if custom_active_video_players == normalized:
		return
	custom_active_video_players = normalized
	performance_profile = PerformanceProfile.CUSTOM
	_commit_change()


func set_custom_active_module_surfaces(value: int) -> void:
	var normalized: int = clampi(value, MIN_MODULE_SURFACES, MAX_MODULE_SURFACES)
	if custom_active_module_surfaces == normalized:
		return
	custom_active_module_surfaces = normalized
	performance_profile = PerformanceProfile.CUSTOM
	_commit_change()


func set_custom_active_note_workspace_surfaces(value: int) -> void:
	var normalized: int = clampi(value, MIN_NOTE_WORKSPACE_SURFACES, MAX_NOTE_WORKSPACE_SURFACES)
	if custom_active_note_workspace_surfaces == normalized:
		return
	custom_active_note_workspace_surfaces = normalized
	performance_profile = PerformanceProfile.CUSTOM
	_commit_change()


func set_custom_full_note_card_render(value: bool) -> void:
	if custom_full_note_card_render == value and performance_profile == PerformanceProfile.CUSTOM:
		return
	custom_full_note_card_render = value
	performance_profile = PerformanceProfile.CUSTOM
	_commit_change()


func set_custom_note_embed_live_media(value: int) -> void:
	var normalized: int = clampi(value, MIN_NOTE_EMBED_LIVE_MEDIA, MAX_NOTE_EMBED_LIVE_MEDIA)
	if custom_note_embed_live_media == normalized and performance_profile == PerformanceProfile.CUSTOM:
		return
	custom_note_embed_live_media = normalized
	performance_profile = PerformanceProfile.CUSTOM
	_commit_change()


func set_custom_note_embed_rich_preview(value: bool) -> void:
	if custom_note_embed_rich_preview == value and performance_profile == PerformanceProfile.CUSTOM:
		return
	custom_note_embed_rich_preview = value
	performance_profile = PerformanceProfile.CUSTOM
	_commit_change()


func set_custom_texture_cache_mb(value: int) -> void:
	var normalized: int = clampi(value, MIN_TEXTURE_CACHE_MB, MAX_TEXTURE_CACHE_MB)
	if custom_texture_cache_mb == normalized:
		return
	custom_texture_cache_mb = normalized
	performance_profile = PerformanceProfile.CUSTOM
	_commit_change()


func set_library_root(value: String) -> void:
	var normalized: String = value.strip_edges()
	if normalized.is_empty():
		normalized = DEFAULT_LIBRARY_ROOT
	if library_root == normalized:
		return
	library_root = normalized
	_commit_change()


func set_module_root(value: String) -> void:
	var normalized: String = value.strip_edges()
	if normalized.is_empty():
		normalized = DEFAULT_MODULE_ROOT
	if module_root == normalized:
		return
	module_root = normalized
	_commit_change()


func set_compression_cpu_mode(value: int) -> void:
	var normalized: CompressionCpuMode = CompressionCpuMode.ECO
	if value == int(CompressionCpuMode.BALANCED):
		normalized = CompressionCpuMode.BALANCED
	elif value == int(CompressionCpuMode.MAXIMUM):
		normalized = CompressionCpuMode.MAXIMUM
	if compression_cpu_mode == normalized:
		return
	compression_cpu_mode = normalized
	_commit_change()


func set_auto_optimize_video(value: bool) -> void:
	if auto_optimize_video == value:
		return
	auto_optimize_video = value
	_commit_change()



func get_drawing_brush_snapshot() -> Dictionary:
	return {
		"style": drawing_style,
		"color": drawing_color,
		"width": drawing_width,
		"eraser_radius": drawing_eraser_radius,
		"spray_spread": drawing_spray_spread,
	}


func set_drawing_brush(style_id: int, color: Color, width: float, spray_spread: float = 1.0) -> void:
	var clean_style: int = clampi(style_id, StrokeStore.STYLE_PEN, StrokeStore.STYLE_SPRAY)
	var clean_width: float = clampf(width, StrokeStore.MIN_WIDTH, StrokeStore.editor_max_width_for_style(clean_style))
	var clean_spread: float = clampf(spray_spread, StrokeStore.MIN_SPRAY_SPREAD, StrokeStore.MAX_SPRAY_SPREAD)
	if drawing_style == clean_style and drawing_color == color and is_equal_approx(drawing_width, clean_width) and is_equal_approx(drawing_spray_spread, clean_spread):
		return
	drawing_style = clean_style
	drawing_color = color
	drawing_width = clean_width
	drawing_spray_spread = clean_spread
	_commit_change(true)


func set_drawing_eraser_radius(value: float) -> void:
	var clean: float = clampf(value, 6.0, 56.0)
	if is_equal_approx(drawing_eraser_radius, clean):
		return
	drawing_eraser_radius = clean
	_commit_change(true)


func list_user_drawing_presets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_id: Variant in user_drawing_presets.keys():
		var preset_id: String = str(raw_id)
		var raw_record: Variant = user_drawing_presets.get(preset_id, {})
		if raw_record is Dictionary:
			var record: Dictionary = (raw_record as Dictionary).duplicate(true)
			record["id"] = preset_id
			result.append(record)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("name", "")).naturalnocasecmp_to(str(right.get("name", ""))) < 0
	)
	return result


func save_user_drawing_preset(display_name: String, style_id: int, color: Color, width: float, spray_spread: float = 1.0) -> String:
	var name: String = _sanitize_drawing_preset_name(display_name)
	if name.is_empty():
		return ""
	var preset_id: String = _find_drawing_preset_id_by_name(name)
	if preset_id.is_empty():
		if user_drawing_presets.size() >= MAX_DRAWING_PRESETS:
			return ""
		preset_id = _make_drawing_preset_id(name)
	var now: int = int(Time.get_unix_time_from_system())
	var previous: Dictionary = user_drawing_presets.get(preset_id, {}) as Dictionary
	user_drawing_presets[preset_id] = {
		"name": name,
		"style": clampi(style_id, StrokeStore.STYLE_PEN, StrokeStore.STYLE_SPRAY),
		"color": color.to_html(true),
		"width": clampf(width, StrokeStore.MIN_WIDTH, StrokeStore.editor_max_width_for_style(style_id)),
		"spray_spread": clampf(spray_spread, StrokeStore.MIN_SPRAY_SPREAD, StrokeStore.MAX_SPRAY_SPREAD),
		"created_at_unix": int(previous.get("created_at_unix", now)),
		"updated_at_unix": now,
	}
	_commit_change()
	return preset_id


func delete_user_drawing_preset(preset_id: String) -> bool:
	var clean: String = preset_id.strip_edges()
	if clean.is_empty() or not user_drawing_presets.has(clean):
		return false
	user_drawing_presets.erase(clean)
	_commit_change()
	return true

func reset_defaults(save_changes: bool = true, preserve_performance: bool = false) -> void:
	var preserved_library_root: String = library_root
	var preserved_module_root: String = module_root
	var preserved_profile: PerformanceProfile = performance_profile
	var preserved_board_budget: int = custom_board_object_budget
	var preserved_ui_budget: int = custom_materialized_ui_budget
	var preserved_video_budget: int = custom_active_video_players
	var preserved_module_budget: int = custom_active_module_surfaces
	var preserved_note_workspace_budget: int = custom_active_note_workspace_surfaces
	var preserved_full_note_card_render: bool = custom_full_note_card_render
	var preserved_note_embed_live_media: int = custom_note_embed_live_media
	var preserved_note_embed_rich_preview: bool = custom_note_embed_rich_preview
	var preserved_texture_budget: int = custom_texture_cache_mb
	var preserved_drawing_quality: DrawingQuality = custom_drawing_quality
	var preserved_prefer_maximum_fps: bool = prefer_maximum_fps
	var preserved_palette_presets: Dictionary = user_palette_presets.duplicate(true)
	var preserved_drawing_presets: Dictionary = user_drawing_presets.duplicate(true)
	input_mode = InputMode.TRACKPAD
	camera_sensitivity = DEFAULT_CAMERA_SENSITIVITY
	zoom_sensitivity = DEFAULT_ZOOM_SENSITIVITY
	camera_speed = DEFAULT_CAMERA_SPEED
	locale = DEFAULT_LOCALE
	window_mode = WindowModePreference.MAXIMIZED
	palette_id = NotLightPalette.PRESET_DEFAULT
	custom_palette = NotLightPalette.default_palette()
	grid_intensity = GridIntensity.BALANCED
	user_palette_presets = preserved_palette_presets
	drawing_style = StrokeStore.STYLE_PEN
	drawing_color = Color("#245cff")
	drawing_width = 4.0
	drawing_eraser_radius = 18.0
	drawing_spray_spread = 1.0
	user_drawing_presets = preserved_drawing_presets
	show_fps = true
	show_ram = false
	show_cpu = false
	show_gpu = false
	show_vram = false
	show_battery = false
	show_tool_hints = true
	monitor_interval_seconds = 1.0
	developer_diagnostics_enabled = false
	prefer_maximum_fps = false
	microphone_consent_state = MICROPHONE_CONSENT_UNKNOWN
	audio_master_enabled = true
	audio_master_volume = DEFAULT_AUDIO_MASTER_VOLUME
	background_music_enabled = false
	background_music_volume = DEFAULT_BACKGROUND_MUSIC_VOLUME
	background_music_track = ""
	background_music_asset_id = ""
	performance_profile = PerformanceProfile.AUTO
	custom_board_object_budget = 12000
	custom_materialized_ui_budget = 96
	custom_active_video_players = 10
	custom_active_module_surfaces = 3
	custom_active_note_workspace_surfaces = DEFAULT_NOTE_WORKSPACE_SURFACES
	custom_full_note_card_render = false
	custom_note_embed_live_media = DEFAULT_NOTE_EMBED_LIVE_MEDIA
	custom_note_embed_rich_preview = true
	custom_texture_cache_mb = 512
	custom_drawing_quality = DrawingQuality.HIGH
	if preserve_performance:
		performance_profile = preserved_profile
		custom_board_object_budget = preserved_board_budget
		custom_materialized_ui_budget = preserved_ui_budget
		custom_active_video_players = preserved_video_budget
		custom_active_module_surfaces = preserved_module_budget
		custom_active_note_workspace_surfaces = preserved_note_workspace_budget
		custom_full_note_card_render = preserved_full_note_card_render
		custom_note_embed_live_media = preserved_note_embed_live_media
		custom_note_embed_rich_preview = preserved_note_embed_rich_preview
		custom_texture_cache_mb = preserved_texture_budget
		custom_drawing_quality = preserved_drawing_quality
		prefer_maximum_fps = preserved_prefer_maximum_fps
	library_root = preserved_library_root if save_changes else DEFAULT_LIBRARY_ROOT
	module_root = preserved_module_root if save_changes else DEFAULT_MODULE_ROOT
	compression_cpu_mode = CompressionCpuMode.ECO
	auto_optimize_video = false
	NotLightL10n.set_locale(locale)
	if save_changes:
		_commit_change()


func save() -> bool:
	_last_error = ""
	var success: bool = _write_json_atomic(SETTINGS_PATH, get_snapshot())
	if success:
		_pending_save = false
	return success


func flush_pending_save() -> bool:
	if not _pending_save:
		return true
	_ensure_save_timer()
	_save_timer.stop()
	if not save():
		settings_error.emit(_last_error)
		return false
	return true


func _set_monitor_flag(kind: String, value: bool) -> void:
	var changed: bool = false
	match kind:
		"fps":
			changed = show_fps != value
			show_fps = value
		"ram":
			changed = show_ram != value
			show_ram = value
		"cpu":
			changed = show_cpu != value
			show_cpu = value
		"gpu":
			changed = show_gpu != value
			show_gpu = value
		"vram":
			changed = show_vram != value
			show_vram = value
		"battery":
			changed = show_battery != value
			show_battery = value
	if changed:
		_commit_change()


func _budget(
	objects: int,
	materialized: int,
	videos: int,
	modules: int,
	note_workspaces: int,
	texture_mb: int,
	full_note_card_render: bool,
	note_embed_live_media: int,
	note_embed_rich_preview: bool
) -> Dictionary:
	return {
		"board_object_budget": clampi(objects, MIN_BOARD_OBJECT_BUDGET, MAX_BOARD_OBJECT_BUDGET),
		"materialized_ui_budget": clampi(materialized, MIN_MATERIALIZED_UI_BUDGET, MAX_MATERIALIZED_UI_BUDGET),
		"active_video_players": clampi(videos, MIN_VIDEO_PLAYERS, MAX_VIDEO_PLAYERS),
		"active_module_surfaces": clampi(modules, MIN_MODULE_SURFACES, MAX_MODULE_SURFACES),
		"active_note_workspace_surfaces": clampi(
			note_workspaces,
			MIN_NOTE_WORKSPACE_SURFACES,
			MAX_NOTE_WORKSPACE_SURFACES
		),
		"texture_cache_mb": clampi(texture_mb, MIN_TEXTURE_CACHE_MB, MAX_TEXTURE_CACHE_MB),
		"full_note_card_render": full_note_card_render,
		"note_embed_live_media": clampi(note_embed_live_media, MIN_NOTE_EMBED_LIVE_MEDIA, MAX_NOTE_EMBED_LIVE_MEDIA),
		"note_embed_rich_preview": note_embed_rich_preview,
	}


func _auto_profile() -> int:
	var cores: int = maxi(1, OS.get_processor_count())
	var memory_info: Dictionary = OS.get_memory_info()
	var physical_bytes: int = int(memory_info.get("physical", -1))
	var physical_gib: float = float(physical_bytes) / 1073741824.0 if physical_bytes > 0 else 8.0
	if cores <= 4 or physical_gib < 8.0:
		return int(PerformanceProfile.ECO)
	if cores >= 12 and physical_gib >= 16.0:
		return int(PerformanceProfile.PERFORMANCE)
	return int(PerformanceProfile.BALANCED)


func _is_valid_palette_id(candidate: String) -> bool:
	return NotLightPalette.preset_ids().has(candidate) or user_palette_presets.has(candidate)


func _sanitize_palette_preset_name(value: String) -> String:
	var clean: String = value.strip_edges().replace("\n", " ").replace("\r", " ").replace("\t", " ")
	while clean.contains("  "):
		clean = clean.replace("  ", " ")
	if clean.length() > MAX_USER_PALETTE_NAME_LENGTH:
		clean = clean.left(MAX_USER_PALETTE_NAME_LENGTH).strip_edges()
	return clean


func _find_user_palette_id_by_name(display_name: String) -> String:
	var target: String = display_name.to_lower()
	for raw_id: Variant in user_palette_presets.keys():
		var preset_id: String = str(raw_id)
		var raw_record: Variant = user_palette_presets.get(preset_id, {})
		if raw_record is Dictionary:
			var record: Dictionary = raw_record as Dictionary
			if str(record.get("name", "")).to_lower() == target:
				return preset_id
	return ""


func _make_user_palette_id(display_name: String) -> String:
	var base: String = "user_%d_%d" % [Time.get_ticks_msec(), absi(display_name.hash())]
	var candidate: String = base
	var suffix: int = 2
	while user_palette_presets.has(candidate):
		candidate = "%s_%d" % [base, suffix]
		suffix += 1
	return candidate


func _sanitize_user_palette_presets(raw_value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if raw_value is not Dictionary:
		return result
	var source: Dictionary = raw_value as Dictionary
	for raw_id: Variant in source.keys():
		if result.size() >= MAX_USER_PALETTE_PRESETS:
			break
		var preset_id: String = str(raw_id).strip_edges()
		if not preset_id.begins_with("user_") or result.has(preset_id):
			continue
		var raw_record: Variant = source.get(raw_id, {})
		if raw_record is not Dictionary:
			continue
		var record: Dictionary = raw_record as Dictionary
		var name: String = _sanitize_palette_preset_name(str(record.get("name", "")))
		if name.is_empty():
			continue
		var raw_colors: Variant = record.get("colors", {})
		if raw_colors is not Dictionary:
			continue
		result[preset_id] = {
			"name": name,
			"colors": NotLightPalette.sanitize_custom(raw_colors as Dictionary),
			"created_at_unix": maxi(0, int(record.get("created_at_unix", 0))),
			"updated_at_unix": maxi(0, int(record.get("updated_at_unix", 0))),
		}
	return result



func _sanitize_drawing_preset_name(value: String) -> String:
	var clean: String = value.strip_edges().replace("\n", " ").replace("\r", " ").replace("\t", " ")
	while clean.contains("  "):
		clean = clean.replace("  ", " ")
	return clean.left(MAX_DRAWING_PRESET_NAME_LENGTH).strip_edges()


func _find_drawing_preset_id_by_name(display_name: String) -> String:
	var target: String = display_name.to_lower()
	for raw_id: Variant in user_drawing_presets.keys():
		var preset_id: String = str(raw_id)
		var record: Dictionary = user_drawing_presets.get(preset_id, {}) as Dictionary
		if str(record.get("name", "")).to_lower() == target:
			return preset_id
	return ""


func _make_drawing_preset_id(display_name: String) -> String:
	var base: String = "draw_%d_%d" % [Time.get_ticks_msec(), absi(display_name.hash())]
	var candidate: String = base
	var suffix: int = 2
	while user_drawing_presets.has(candidate):
		candidate = "%s_%d" % [base, suffix]
		suffix += 1
	return candidate


func _sanitize_user_drawing_presets(raw_value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if raw_value is not Dictionary:
		return result
	var source: Dictionary = raw_value as Dictionary
	for raw_id: Variant in source.keys():
		if result.size() >= MAX_DRAWING_PRESETS:
			break
		var preset_id: String = str(raw_id).strip_edges()
		var raw_record: Variant = source.get(raw_id, {})
		if not preset_id.begins_with("draw_") or raw_record is not Dictionary:
			continue
		var record: Dictionary = raw_record as Dictionary
		var name: String = _sanitize_drawing_preset_name(str(record.get("name", "")))
		if name.is_empty():
			continue
		result[preset_id] = {
			"name": name,
			"style": clampi(int(record.get("style", StrokeStore.STYLE_PEN)), StrokeStore.STYLE_PEN, StrokeStore.STYLE_SPRAY),
			"color": Color.from_string(str(record.get("color", "#245cffff")), Color("#245cff")).to_html(true),
			"width": clampf(float(record.get("width", 4.0)), StrokeStore.MIN_WIDTH, StrokeStore.MAX_WIDTH),
			"spray_spread": clampf(float(record.get("spray_spread", 1.0)), StrokeStore.MIN_SPRAY_SPREAD, StrokeStore.MAX_SPRAY_SPREAD),
			"created_at_unix": maxi(0, int(record.get("created_at_unix", 0))),
			"updated_at_unix": maxi(0, int(record.get("updated_at_unix", 0))),
		}
	return result

func _commit_change(interactive: bool = false) -> void:
	_pending_save = true
	if interactive:
		_pending_settings_broadcast = true
		_ensure_interactive_broadcast_timer()
		_interactive_broadcast_timer.start(INTERACTIVE_BROADCAST_DEBOUNCE_SECONDS)
	else:
		_pending_settings_broadcast = false
		if _interactive_broadcast_timer != null:
			_interactive_broadcast_timer.stop()
		settings_changed.emit(get_snapshot())
	_ensure_save_timer()
	_save_timer.start(SAVE_DEBOUNCE_SECONDS)


func _ensure_interactive_broadcast_timer() -> void:
	if _interactive_broadcast_timer != null:
		return
	_interactive_broadcast_timer = Timer.new()
	_interactive_broadcast_timer.name = "SettingsInteractiveBroadcastDebounce"
	_interactive_broadcast_timer.one_shot = true
	_interactive_broadcast_timer.wait_time = INTERACTIVE_BROADCAST_DEBOUNCE_SECONDS
	_interactive_broadcast_timer.timeout.connect(_flush_pending_settings_broadcast)
	add_child(_interactive_broadcast_timer)


func _flush_pending_settings_broadcast() -> void:
	if not _pending_settings_broadcast:
		return
	_pending_settings_broadcast = false
	settings_changed.emit(get_snapshot())


func _ensure_save_timer() -> void:
	if _save_timer != null:
		return
	_save_timer = Timer.new()
	_save_timer.name = "SettingsSaveDebounce"
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DEBOUNCE_SECONDS
	_save_timer.timeout.connect(_on_save_timer_timeout)
	add_child(_save_timer)


func _on_save_timer_timeout() -> void:
	flush_pending_save()


func _apply_dictionary(source: Dictionary) -> void:
	var raw_mode: int = int(source.get("input_mode", int(InputMode.TRACKPAD)))
	input_mode = InputMode.TRACKPAD if raw_mode == int(InputMode.TRACKPAD) else InputMode.MOUSE
	camera_sensitivity = clampf(float(source.get("camera_sensitivity", DEFAULT_CAMERA_SENSITIVITY)), 0.25, 3.0)
	zoom_sensitivity = clampf(float(source.get("zoom_sensitivity", DEFAULT_ZOOM_SENSITIVITY)), 0.25, 3.0)
	camera_speed = clampf(float(source.get("camera_speed", DEFAULT_CAMERA_SPEED)), 3.0, 30.0)
	locale = str(source.get("locale", DEFAULT_LOCALE)).strip_edges().to_lower()
	if not NotLightL10n.available_locales().has(locale):
		locale = DEFAULT_LOCALE
	NotLightL10n.set_locale(locale)
	window_mode = _window_mode_from_int(int(source.get("window_mode", int(WindowModePreference.MAXIMIZED))))
	grid_intensity = _grid_intensity_from_int(int(source.get("grid_intensity", int(GridIntensity.BALANCED))))
	user_palette_presets = _sanitize_user_palette_presets(source.get("user_palette_presets", {}))
	drawing_style = clampi(int(source.get("drawing_style", StrokeStore.STYLE_PEN)), StrokeStore.STYLE_PEN, StrokeStore.STYLE_SPRAY)
	drawing_color = Color.from_string(str(source.get("drawing_color", "#245cffff")), Color("#245cff"))
	drawing_width = clampf(float(source.get("drawing_width", 4.0)), StrokeStore.MIN_WIDTH, StrokeStore.editor_max_width_for_style(drawing_style))
	drawing_eraser_radius = clampf(float(source.get("drawing_eraser_radius", 18.0)), 6.0, 56.0)
	drawing_spray_spread = clampf(float(source.get("drawing_spray_spread", 1.0)), StrokeStore.MIN_SPRAY_SPREAD, StrokeStore.MAX_SPRAY_SPREAD)
	user_drawing_presets = _sanitize_user_drawing_presets(source.get("user_drawing_presets", {}))
	palette_id = str(source.get("palette_id", NotLightPalette.PRESET_DEFAULT)).strip_edges()
	# Stage 8.2 exposed a dark preset whose monochrome SVG assets were not
	# authored for dark surfaces. Migrate it safely back to the default palette.
	if palette_id == "dark" or not _is_valid_palette_id(palette_id):
		palette_id = NotLightPalette.PRESET_DEFAULT
	var custom_value: Variant = source.get("custom_palette", {})
	var custom_dictionary: Dictionary = {}
	if custom_value is Dictionary:
		custom_dictionary = (custom_value as Dictionary).duplicate(true)
	custom_palette = NotLightPalette.sanitize_custom(custom_dictionary)
	if user_palette_presets.has(palette_id):
		var selected_record: Dictionary = user_palette_presets.get(palette_id, {}) as Dictionary
		var selected_colors: Variant = selected_record.get("colors", {})
		if selected_colors is Dictionary:
			custom_palette = NotLightPalette.sanitize_custom(selected_colors as Dictionary)
	show_fps = bool(source.get("show_fps", true))
	show_ram = bool(source.get("show_ram", false))
	show_cpu = bool(source.get("show_cpu", false))
	show_gpu = bool(source.get("show_gpu", false))
	show_vram = bool(source.get("show_vram", false))
	show_battery = bool(source.get("show_battery", false))
	show_tool_hints = bool(source.get("show_tool_hints", true))
	monitor_interval_seconds = clampf(float(source.get("monitor_interval_seconds", 1.0)), 0.5, 5.0)
	developer_diagnostics_enabled = bool(source.get("developer_diagnostics_enabled", false))
	prefer_maximum_fps = bool(source.get("prefer_maximum_fps", false))
	microphone_consent_state = clampi(
		int(source.get("microphone_consent_state", MICROPHONE_CONSENT_UNKNOWN)),
		MICROPHONE_CONSENT_UNKNOWN,
		MICROPHONE_CONSENT_DECLINED
	)
	audio_master_enabled = bool(source.get("audio_master_enabled", true))
	audio_master_volume = clampf(float(source.get("audio_master_volume", DEFAULT_AUDIO_MASTER_VOLUME)), 0.0, 1.0)
	background_music_enabled = bool(source.get("background_music_enabled", false))
	background_music_volume = clampf(float(source.get("background_music_volume", DEFAULT_BACKGROUND_MUSIC_VOLUME)), 0.0, 1.0)
	background_music_track = _sanitize_background_music_track(str(source.get("background_music_track", "")))
	background_music_asset_id = _sanitize_asset_id(str(source.get("background_music_asset_id", "")))
	if not background_music_asset_id.is_empty():
		background_music_track = ""
	performance_profile = _performance_profile_from_int(int(source.get("performance_profile", int(PerformanceProfile.AUTO))))
	custom_board_object_budget = clampi(int(source.get("custom_board_object_budget", 12000)), MIN_BOARD_OBJECT_BUDGET, MAX_BOARD_OBJECT_BUDGET)
	custom_materialized_ui_budget = clampi(int(source.get("custom_materialized_ui_budget", 96)), MIN_MATERIALIZED_UI_BUDGET, MAX_MATERIALIZED_UI_BUDGET)
	custom_active_video_players = clampi(int(source.get("custom_active_video_players", 10)), MIN_VIDEO_PLAYERS, MAX_VIDEO_PLAYERS)
	custom_active_module_surfaces = clampi(int(source.get("custom_active_module_surfaces", 3)), MIN_MODULE_SURFACES, MAX_MODULE_SURFACES)
	custom_active_note_workspace_surfaces = clampi(
		int(source.get("custom_active_note_workspace_surfaces", DEFAULT_NOTE_WORKSPACE_SURFACES)),
		MIN_NOTE_WORKSPACE_SURFACES,
		MAX_NOTE_WORKSPACE_SURFACES
	)
	custom_full_note_card_render = bool(source.get("custom_full_note_card_render", false))
	custom_note_embed_live_media = clampi(
		int(source.get("custom_note_embed_live_media", DEFAULT_NOTE_EMBED_LIVE_MEDIA)),
		MIN_NOTE_EMBED_LIVE_MEDIA,
		MAX_NOTE_EMBED_LIVE_MEDIA
	)
	custom_note_embed_rich_preview = bool(source.get("custom_note_embed_rich_preview", true))
	custom_texture_cache_mb = clampi(int(source.get("custom_texture_cache_mb", 512)), MIN_TEXTURE_CACHE_MB, MAX_TEXTURE_CACHE_MB)
	custom_drawing_quality = _drawing_quality_from_int(int(source.get("custom_drawing_quality", int(DrawingQuality.HIGH))))
	library_root = str(source.get("library_root", DEFAULT_LIBRARY_ROOT)).strip_edges()
	if library_root.is_empty():
		library_root = DEFAULT_LIBRARY_ROOT
	module_root = str(source.get("module_root", DEFAULT_MODULE_ROOT)).strip_edges()
	if module_root.is_empty():
		module_root = DEFAULT_MODULE_ROOT
	var raw_cpu_mode: int = int(source.get("compression_cpu_mode", int(CompressionCpuMode.ECO)))
	compression_cpu_mode = CompressionCpuMode.ECO
	if raw_cpu_mode == int(CompressionCpuMode.BALANCED):
		compression_cpu_mode = CompressionCpuMode.BALANCED
	elif raw_cpu_mode == int(CompressionCpuMode.MAXIMUM):
		compression_cpu_mode = CompressionCpuMode.MAXIMUM
	auto_optimize_video = bool(source.get("auto_optimize_video", false))



func _sanitize_background_music_track(value: String) -> String:
	var clean: String = value.strip_edges().replace("\\", "/")
	if clean.is_empty():
		return ""
	if not clean.begins_with(BACKGROUND_MUSIC_ROOT + "/"):
		return ""
	var extension: String = clean.get_extension().to_lower()
	if not PackedStringArray(["ogg", "mp3", "wav"]).has(extension):
		return ""
	return clean


func _sanitize_asset_id(value: String) -> String:
	var clean: String = value.strip_edges()
	if clean.is_empty() or clean.length() > 256:
		return ""
	if clean.contains("/") or clean.contains("\\"):
		return ""
	return clean


func _drawing_quality_from_int(value: int) -> DrawingQuality:
	match value:
		int(DrawingQuality.ECO):
			return DrawingQuality.ECO
		int(DrawingQuality.BALANCED):
			return DrawingQuality.BALANCED
		int(DrawingQuality.ULTRA):
			return DrawingQuality.ULTRA
		_:
			return DrawingQuality.HIGH


func _grid_intensity_from_int(value: int) -> GridIntensity:
	match value:
		int(GridIntensity.SOFT):
			return GridIntensity.SOFT
		int(GridIntensity.EXPRESSIVE):
			return GridIntensity.EXPRESSIVE
		_:
			return GridIntensity.BALANCED


func _window_mode_from_int(value: int) -> WindowModePreference:
	match value:
		int(WindowModePreference.MAXIMIZED):
			return WindowModePreference.MAXIMIZED
		int(WindowModePreference.FULLSCREEN):
			return WindowModePreference.FULLSCREEN
		_:
			return WindowModePreference.WINDOWED


func _performance_profile_from_int(value: int) -> PerformanceProfile:
	match value:
		int(PerformanceProfile.ECO):
			return PerformanceProfile.ECO
		int(PerformanceProfile.BALANCED):
			return PerformanceProfile.BALANCED
		int(PerformanceProfile.PERFORMANCE):
			return PerformanceProfile.PERFORMANCE
		int(PerformanceProfile.CUSTOM):
			return PerformanceProfile.CUSTOM
		_:
			return PerformanceProfile.AUTO

func _write_json_atomic(path: String, data: Dictionary) -> bool:
	if not _ensure_directory(path.get_base_dir()):
		return false
	var temporary_path: String = "%s.tmp" % path
	var backup_path: String = "%s.bak" % path
	var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		_fail(NotLightL10n.text("runtime.settings.write_open_failed"))
		return false
	var write_ok: bool = file.store_string(JSON.stringify(data, "  ", false, true))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if not write_ok or write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		_fail(NotLightL10n.text("runtime.settings.write_incomplete"))
		return false
	var absolute_path: String = ProjectSettings.globalize_path(path)
	var absolute_temporary: String = ProjectSettings.globalize_path(temporary_path)
	var absolute_backup: String = ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(absolute_backup)
	if FileAccess.file_exists(path):
		var backup_error: Error = DirAccess.rename_absolute(absolute_path, absolute_backup)
		if backup_error != OK:
			DirAccess.remove_absolute(absolute_temporary)
			_fail(NotLightL10n.text("runtime.settings.backup_failed"))
			return false
	var replace_error: Error = DirAccess.rename_absolute(absolute_temporary, absolute_path)
	if replace_error != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(absolute_backup, absolute_path)
		if FileAccess.file_exists(temporary_path):
			DirAccess.remove_absolute(absolute_temporary)
		_fail(NotLightL10n.text("runtime.settings.replace_failed"))
		return false
	return true


func _read_json_with_backup(path: String) -> Dictionary:
	var primary: Dictionary = _read_json(path)
	if not primary.is_empty():
		return primary
	return _read_json("%s.bak" % path)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		return {}
	return (parsed as Dictionary).duplicate(true)


func _ensure_directory(path: String) -> bool:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(absolute_path):
		return true
	var error: Error = DirAccess.make_dir_recursive_absolute(absolute_path)
	if error != OK:
		_fail(NotLightL10n.text("runtime.settings.mkdir_failed"))
		return false
	return true


func _fail(message: String) -> void:
	_last_error = message
	push_error(message)
