# SPDX-License-Identifier: GPL-3.0-or-later
class_name AppRoot
extends Control

var repository: BoardRepository
var session: BoardSession
var settings: AppSettingsStore
var asset_library: AssetLibraryService
var note_repository: NoteRepository
var portable_packages: NotLightPortablePackageService
var module_registry: ModuleRegistry
var module_packages: ModulePackageService
var image_cache: ImageAssetCache
var pdf_media: PdfMediaService
var pdf_optimizer: PdfOptimizationService
var video_media: VideoMediaService
var audio_media: AudioMediaService
var app_audio: AppAudioService
var voice_recording: VoiceRecordingService
var telemetry: PerformanceTelemetryService
var formula_render: FormulaRenderService
var power_status: PowerStatusService
var _current_screen: Control
var _transition_blocker: bool = false
var _applied_window_mode: int = -1
var _baseline_max_fps: int = 0
var _baseline_vsync_mode: int = int(DisplayServer.VSYNC_ENABLED)
var _frame_rate_baseline_captured: bool = false


func _ready() -> void:
	get_tree().auto_accept_quit = false
	if not NotLightL10n.initialize():
		push_error(NotLightL10n.get_last_error())
	_configure_desktop_content_scaling()
	CursorThemeService.install()
	get_window().min_size = Vector2i(960, 640)
	_capture_frame_rate_baseline()

	settings = AppSettingsStore.new()
	settings.name = "AppSettings"
	add_child(settings)
	if not settings.setup():
		push_error(settings.get_last_error())
	_adopt_legacy_storage_roots_if_safe()

	repository = BoardRepository.new()
	repository.name = "BoardRepository"
	add_child(repository)
	if not repository.setup(settings.board_root):
		push_error(repository.get_last_error())
	_apply_application_settings(settings.get_snapshot())
	if not settings.settings_changed.is_connected(_apply_application_settings):
		settings.settings_changed.connect(_apply_application_settings)

	app_audio = AppAudioService.new()
	app_audio.name = "AppAudioService"
	add_child(app_audio)
	app_audio.configure(settings)

	session = BoardSession.new()
	session.name = "BoardSession"
	add_child(session)
	session.configure(repository)

	asset_library = AssetLibraryService.new()
	asset_library.name = "AssetLibrary"
	add_child(asset_library)
	if not asset_library.setup(repository, settings.library_root):
		# Never silently fall back to a second library: if an external drive is
		# missing, creating a fresh local catalog would split stable asset IDs.
		push_error(NotLightL10n.text("runtime.app.resource_library_unavailable") % asset_library.get_last_error())

	note_repository = NoteRepository.new()
	note_repository.name = "NoteRepository"
	add_child(note_repository)
	note_repository.configure(asset_library)

	portable_packages = NotLightPortablePackageService.new()
	portable_packages.name = "PortablePackages"
	add_child(portable_packages)
	portable_packages.configure(repository, asset_library, note_repository)

	module_registry = ModuleRegistry.new()
	module_registry.name = "ModuleRegistry"
	add_child(module_registry)
	module_registry.configure(repository, settings.module_root)
	if not module_registry.setup():
		push_error(NotLightL10n.text("runtime.app.module_registry_unavailable") % module_registry.get_last_error())

	module_packages = ModulePackageService.new()
	module_packages.name = "ModulePackages"
	add_child(module_packages)
	module_packages.configure(module_registry)

	image_cache = ImageAssetCache.new()
	image_cache.name = "ImageAssetCache"
	add_child(image_cache)
	image_cache.configure(asset_library)
	_apply_image_cache_budget()

	pdf_media = PdfMediaService.new()
	pdf_media.name = "PdfMediaService"
	add_child(pdf_media)
	pdf_media.configure(asset_library)
	_apply_image_cache_budget()

	pdf_optimizer = PdfOptimizationService.new()
	pdf_optimizer.name = "PdfOptimizationService"
	add_child(pdf_optimizer)
	pdf_optimizer.configure(asset_library, pdf_media)

	video_media = VideoMediaService.new()
	video_media.name = "VideoMediaService"
	add_child(video_media)
	video_media.configure(asset_library, settings)

	audio_media = AudioMediaService.new()
	audio_media.name = "AudioMediaService"
	add_child(audio_media)
	audio_media.configure(asset_library)
	app_audio.configure_library(asset_library, audio_media)

	voice_recording = VoiceRecordingService.new()
	voice_recording.name = "VoiceRecordingService"
	add_child(voice_recording)
	voice_recording.configure(asset_library)

	formula_render = FormulaRenderService.new()
	formula_render.name = "FormulaRenderService"
	add_child(formula_render)

	power_status = PowerStatusService.new()
	power_status.name = "PowerStatusService"
	add_child(power_status)
	power_status.configure(settings)

	telemetry = PerformanceTelemetryService.new()
	telemetry.name = "PerformanceTelemetry"
	add_child(telemetry)
	telemetry.configure(settings)
	image_cache.configure_telemetry(telemetry)

	_show_hub()


func _adopt_legacy_storage_roots_if_safe() -> void:
	if settings == null:
		return
	var current_user_dir: String = OS.get_user_data_dir().simplify_path()
	var app_userdata_parent: String = current_user_dir.get_base_dir()
	var legacy_notlight_root: String = app_userdata_parent.path_join("NotLight Board").path_join("notlight").simplify_path()
	if not DirAccess.dir_exists_absolute(legacy_notlight_root):
		return
	var changed: bool = false
	var current_board_root: String = ProjectSettings.globalize_path(AppSettingsStore.DEFAULT_BOARD_ROOT).simplify_path()
	var legacy_board_root: String = legacy_notlight_root
	if settings.board_root == AppSettingsStore.DEFAULT_BOARD_ROOT and not _board_storage_has_user_data(current_board_root) and _board_storage_has_user_data(legacy_board_root):
		settings.set_board_root(legacy_board_root)
		changed = true
	var current_library_root: String = ProjectSettings.globalize_path(AppSettingsStore.DEFAULT_LIBRARY_ROOT).simplify_path()
	var legacy_library_root: String = legacy_notlight_root.path_join("library")
	if settings.library_root == AppSettingsStore.DEFAULT_LIBRARY_ROOT and not _library_storage_has_user_data(current_library_root) and _library_storage_has_user_data(legacy_library_root):
		settings.set_library_root(legacy_library_root)
		changed = true
	var current_module_root: String = ProjectSettings.globalize_path(AppSettingsStore.DEFAULT_MODULE_ROOT).simplify_path()
	var legacy_module_root: String = legacy_notlight_root.path_join("modules")
	if settings.module_root == AppSettingsStore.DEFAULT_MODULE_ROOT and not _module_storage_has_user_data(current_module_root) and _module_storage_has_user_data(legacy_module_root):
		settings.set_module_root(legacy_module_root)
		changed = true
	if changed and not settings.flush_pending_save():
		push_error(settings.get_last_error())


func _board_storage_has_user_data(root: String) -> bool:
	var boards: String = root.path_join("boards")
	if not DirAccess.dir_exists_absolute(boards):
		return false
	return not DirAccess.get_directories_at(boards).is_empty()


func _library_storage_has_user_data(root: String) -> bool:
	var catalog_path: String = root.path_join("catalog.json")
	if not FileAccess.file_exists(catalog_path):
		return false
	var file: FileAccess = FileAccess.open(catalog_path, FileAccess.READ)
	if file == null:
		return true
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is not Dictionary:
		return true
	var source: Dictionary = parsed as Dictionary
	var assets: Variant = source.get("assets", [])
	var folders: Variant = source.get("folders", [])
	return (assets is Array and not (assets as Array).is_empty()) or (folders is Array and not (folders as Array).is_empty())


func _module_storage_has_user_data(root: String) -> bool:
	if not DirAccess.dir_exists_absolute(root):
		return false
	for module_id: String in DirAccess.get_directories_at(root):
		if module_id.begins_with("."):
			continue
		var module_root: String = root.path_join(module_id)
		if FileAccess.file_exists(module_root.path_join("state.json")) or DirAccess.dir_exists_absolute(module_root.path_join("versions")):
			return true
	return false


func _configure_desktop_content_scaling() -> void:
	# NotLight is a desktop productivity UI, not a fixed-aspect game viewport.
	# Let Control anchors/layout containers consume the real window dimensions
	# instead of preserving the 1440×900 design aspect and producing pillarbox.
	var root_window: Window = get_tree().root
	if root_window == null:
		return
	root_window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root_window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root_window.content_scale_size = Vector2i.ZERO
	root_window.content_scale_factor = 1.0


func _apply_application_settings(snapshot: Dictionary) -> void:
	theme = NotLightTheme.create_theme(settings.get_effective_palette() if settings != null else NotLightPalette.default_palette())
	_apply_image_cache_budget()
	_apply_frame_rate_policy(bool(snapshot.get("prefer_maximum_fps", false)))
	var root_window: Window = get_window()
	if root_window == null:
		return
	var requested_mode: int = int(snapshot.get("window_mode", int(AppSettingsStore.WindowModePreference.MAXIMIZED)))
	if requested_mode == _applied_window_mode:
		return
	_applied_window_mode = requested_mode
	match requested_mode:
		AppSettingsStore.WindowModePreference.MAXIMIZED:
			root_window.mode = Window.MODE_MAXIMIZED
		AppSettingsStore.WindowModePreference.FULLSCREEN:
			root_window.mode = Window.MODE_FULLSCREEN
		_:
			root_window.mode = Window.MODE_WINDOWED


func _capture_frame_rate_baseline() -> void:
	_baseline_max_fps = Engine.max_fps
	_baseline_vsync_mode = int(DisplayServer.window_get_vsync_mode())
	_frame_rate_baseline_captured = true


func _apply_frame_rate_policy(prefer_maximum: bool) -> void:
	if not _frame_rate_baseline_captured:
		_capture_frame_rate_baseline()
	if prefer_maximum:
		# This removes NotLight/Godot-side frame pacing limits. The operating system,
		# firmware and GPU driver can still enforce battery power limits externally.
		Engine.max_fps = 0
		if int(DisplayServer.window_get_vsync_mode()) != int(DisplayServer.VSYNC_DISABLED):
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		return
	Engine.max_fps = _baseline_max_fps
	if int(DisplayServer.window_get_vsync_mode()) != _baseline_vsync_mode:
		DisplayServer.window_set_vsync_mode(_baseline_vsync_mode)


func _apply_image_cache_budget() -> void:
	if settings == null:
		return
	var budget: Dictionary = settings.get_performance_budget()
	var texture_budget_mb: int = maxi(64, int(budget.get("texture_cache_mb", 512)))
	if image_cache != null:
		image_cache.set_memory_limit_megabytes(texture_budget_mb)
	if pdf_media != null:
		pdf_media.set_memory_limit_megabytes(maxi(128, floori(float(texture_budget_mb) * 0.5)))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_request_application_exit()


func _request_application_exit() -> void:
	_flush_current_view_state()
	if note_repository != null and not note_repository.flush_pending_saves():
		return
	if session != null and not session.current_board_id.is_empty():
		if not session.close_board(true):
			return
	var prepared_board_root: String = ""
	if repository != null and repository.has_prepared_external_boards():
		var boards_finalize: Dictionary = repository.finalize_prepared_external_boards()
		if not bool(boards_finalize.get("ok", false)):
			push_error(str(boards_finalize.get("error", NotLightL10n.text("settings.storage.prepare_boards_failed"))))
			return
		prepared_board_root = str(boards_finalize.get("root", ""))
	var prepared_library_root: String = ""
	if asset_library != null and asset_library.has_prepared_external_library():
		var library_finalize: Dictionary = asset_library.finalize_prepared_external_library()
		if not bool(library_finalize.get("ok", false)):
			push_error(str(library_finalize.get("error", NotLightL10n.text("settings.storage.prepare_failed"))))
			return
		prepared_library_root = str(library_finalize.get("root", ""))
	var prepared_module_root: String = ""
	if module_registry != null and module_registry.has_prepared_external_modules():
		var modules_finalize: Dictionary = module_registry.finalize_prepared_external_modules()
		if not bool(modules_finalize.get("ok", false)):
			push_error(str(modules_finalize.get("error", NotLightL10n.text("settings.storage.prepare_modules_failed"))))
			return
		prepared_module_root = str(modules_finalize.get("root", ""))
	var previous_board_root: String = settings.board_root if settings != null else ""
	var previous_library_root: String = settings.library_root if settings != null else ""
	var previous_module_root: String = settings.module_root if settings != null else ""
	if settings != null:
		if not prepared_board_root.is_empty():
			settings.set_board_root(prepared_board_root)
		if not prepared_library_root.is_empty():
			settings.set_library_root(prepared_library_root)
		if not prepared_module_root.is_empty():
			settings.set_module_root(prepared_module_root)
		if not settings.flush_pending_save():
			if not prepared_board_root.is_empty():
				settings.set_board_root(previous_board_root)
			if not prepared_library_root.is_empty():
				settings.set_library_root(previous_library_root)
			if not prepared_module_root.is_empty():
				settings.set_module_root(previous_module_root)
			settings.flush_pending_save()
			return
	# The settings file now points at the verified destination. Only after that
	# durable switch succeeds do we remove the previous source. If Windows keeps
	# a file locked, the new location remains authoritative and the old copy is
	# retained as a safety backup instead of risking data loss.
	if repository != null and not prepared_board_root.is_empty():
		var board_cleanup: Dictionary = repository.cleanup_migrated_external_board_source()
		if not bool(board_cleanup.get("ok", false)):
			push_warning(str(board_cleanup.get("error", NotLightL10n.text("settings.storage.cleanup_failed") % repository.get_root_directory())))
		repository.mark_prepared_external_boards_activated()
	if asset_library != null and not prepared_library_root.is_empty():
		var library_cleanup: Dictionary = asset_library.cleanup_migrated_external_library_source()
		if not bool(library_cleanup.get("ok", false)):
			push_warning(str(library_cleanup.get("error", NotLightL10n.text("settings.storage.cleanup_failed") % asset_library.get_root_directory())))
		asset_library.mark_prepared_external_library_activated()
	if module_registry != null and not prepared_module_root.is_empty():
		var module_cleanup: Dictionary = module_registry.cleanup_migrated_external_modules_source()
		if not bool(module_cleanup.get("ok", false)):
			push_warning(str(module_cleanup.get("error", NotLightL10n.text("settings.storage.cleanup_failed") % module_registry.get_root_directory())))
		module_registry.mark_prepared_external_modules_activated()
	get_tree().quit()


func _show_hub() -> void:
	if telemetry != null:
		telemetry.set_monitoring_active(false)
	if power_status != null:
		power_status.set_monitoring_active(false)
	_replace_screen(null)
	var hub: HubScreen = HubScreen.new()
	hub.name = "HubScreen"
	hub.board_open_requested.connect(_open_board)
	hub.exit_requested.connect(_request_application_exit)
	_replace_screen(hub)
	hub.configure(repository, asset_library, settings, image_cache, pdf_media, video_media, audio_media, portable_packages, pdf_optimizer, module_registry, module_packages, note_repository, formula_render, app_audio)


func _open_board(board_id: String) -> void:
	if _transition_blocker:
		return
	_transition_blocker = true
	if not session.open_board(board_id):
		_transition_blocker = false
		return
	if telemetry != null:
		telemetry.set_monitoring_active(true)
	if power_status != null:
		power_status.set_monitoring_active(true)
	var board_screen: BoardScreen = BoardScreen.new()
	board_screen.name = "BoardScreen"
	board_screen.back_requested.connect(_return_to_hub)
	_replace_screen(board_screen)
	board_screen.configure(session, settings, asset_library, image_cache, pdf_media, video_media, audio_media, voice_recording, telemetry, pdf_optimizer, formula_render, power_status, module_registry, note_repository, app_audio, repository)
	_transition_blocker = false


func _return_to_hub() -> void:
	if _transition_blocker:
		return
	_transition_blocker = true
	_flush_current_view_state()
	if not session.close_board(true):
		_transition_blocker = false
		return
	_show_hub()
	_transition_blocker = false


func _flush_current_view_state() -> void:
	if _current_screen is BoardScreen:
		(_current_screen as BoardScreen).flush_view_state()


func _replace_screen(next_screen: Control) -> void:
	if _current_screen != null and is_instance_valid(_current_screen):
		_current_screen.queue_free()
		_current_screen = null
	if next_screen == null:
		return
	next_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(next_screen)
	move_child(next_screen, 0)
	_current_screen = next_screen
