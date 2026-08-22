# SPDX-License-Identifier: GPL-3.0-or-later
class_name VideoPlayerOverlay
extends Control

signal closed

var media: VideoMediaService
var asset_id: String = ""
var display_name: String = ""
var duration: float = 0.0

var _video: VideoStreamPlayer
var _aspect: AspectRatioContainer
var _title_label: Label
var _state_label: Label
var _seek: HSlider
var _time_label: Label
var _play_button: Button
var _mute_button: Button
var _volume_slider: HSlider
var _loop_button: Button
var _optimization_label: Label
var _optimization_progress: ProgressBar
var _profile_option: OptionButton
var _optimize_button: Button
var _cancel_optimize_button: Button
var _source_info_label: Label
var _user_seeking: bool = false
var _resume_after_seek: bool = false
var _remembered_volume: float = 0.82
var _window_mode_before_fullscreen: int = DisplayServer.WINDOW_MODE_WINDOWED


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 1600
	_build_ui()
	set_process(false)


func configure(video_media: VideoMediaService) -> void:
	media = video_media
	if media == null:
		return
	if not media.optimization_started.is_connected(_on_optimization_started):
		media.optimization_started.connect(_on_optimization_started)
	if not media.optimization_progress.is_connected(_on_optimization_progress):
		media.optimization_progress.connect(_on_optimization_progress)
	if not media.optimization_completed.is_connected(_on_optimization_completed):
		media.optimization_completed.connect(_on_optimization_completed)
	if not media.optimization_failed.is_connected(_on_optimization_failed):
		media.optimization_failed.connect(_on_optimization_failed)


func open_asset(new_asset_id: String, new_display_name: String = "") -> void:
	if media == null:
		return
	var clean_id: String = new_asset_id.strip_edges()
	if clean_id.is_empty():
		return
	asset_id = clean_id
	display_name = new_display_name.strip_edges()
	var metadata: Dictionary = media.ensure_asset(asset_id)
	if display_name.is_empty() and media.library != null:
		var record: Dictionary = media.library.get_asset(asset_id)
		display_name = str(record.get("display_name", NotLightL10n.text("asset.kind.video")))
	duration = maxf(0.0, float(metadata.get("duration", 0.0)))
	_title_label.text = display_name if not display_name.is_empty() else NotLightL10n.text("asset.kind.video")
	_refresh_source_info(metadata)
	_refresh_optimization_state(metadata)
	visible = true
	set_process(true)
	grab_focus()
	_load_stream(media.resolve_playback_path(asset_id))


func close_player() -> void:
	if _video != null:
		_video.stop()
		_video.stream = null
	asset_id = ""
	display_name = ""
	duration = 0.0
	visible = false
	set_process(false)
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(_window_mode_before_fullscreen)
	closed.emit()


func _build_ui() -> void:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.035, 0.045, 0.040, 0.72)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = "SettingsModalPanel"
	panel.custom_minimum_size = Vector2(940.0, 690.0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)
	var title_box: VBoxContainer = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 1)
	header.add_child(title_box)
	_title_label = Label.new()
	NotLightL10n.bind_text(_title_label, "runtime.ui.video_player_overlay.940814c1c7")
	_title_label.theme_type_variation = "TitleLabel"
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_box.add_child(_title_label)
	_state_label = Label.new()
	NotLightL10n.bind_text(_state_label, "common.done")
	_state_label.theme_type_variation = "CaptionLabel"
	title_box.add_child(_state_label)

	var decoder_badge: Label = Label.new()
	decoder_badge.text = "EIRTeam.FFmpeg"
	decoder_badge.theme_type_variation = "AssetKindLabel"
	header.add_child(decoder_badge)

	var close_button: Button = Button.new()
	close_button.icon = load("res://assets/icons/close.svg") as Texture2D
	NotLightL10n.bind_tooltip(close_button, "runtime.ui.video_player_overlay.5b978364f9")
	close_button.theme_type_variation = "IconButton"
	close_button.custom_minimum_size = Vector2(40.0, 40.0)
	close_button.pressed.connect(close_player)
	header.add_child(close_button)

	var stage_panel: PanelContainer = PanelContainer.new()
	stage_panel.theme_type_variation = "SoftPanel"
	stage_panel.custom_minimum_size = Vector2(0.0, 430.0)
	stage_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(stage_panel)

	var stage: Control = Control.new()
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_PASS
	stage_panel.add_child(stage)

	var dark: ColorRect = ColorRect.new()
	dark.color = Color("#151a17")
	dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(dark)

	_aspect = AspectRatioContainer.new()
	_aspect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_aspect.ratio = 16.0 / 9.0
	_aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	_aspect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_aspect)

	_video = VideoStreamPlayer.new()
	_video.expand = true
	_video.volume = _remembered_volume
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video.finished.connect(_on_video_finished)
	_aspect.add_child(_video)
	_video.add_to_group(AppAudioService.FOREGROUND_MEDIA_GROUP)

	stage.gui_input.connect(_on_stage_input)

	var controls_panel: PanelContainer = PanelContainer.new()
	controls_panel.theme_type_variation = "SettingsSectionPanel"
	root.add_child(controls_panel)
	var controls: VBoxContainer = VBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	controls_panel.add_child(controls)

	var seek_row: HBoxContainer = HBoxContainer.new()
	seek_row.add_theme_constant_override("separation", 10)
	controls.add_child(seek_row)
	_seek = HSlider.new()
	_seek.scrollable = false
	_seek.min_value = 0.0
	_seek.max_value = 1.0
	_seek.step = 0.01
	_seek.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seek.custom_minimum_size = Vector2(0.0, 24.0)
	_seek.drag_started.connect(_on_seek_drag_started)
	_seek.drag_ended.connect(_on_seek_drag_ended)
	_seek.value_changed.connect(_on_seek_value_changed)
	seek_row.add_child(_seek)
	_time_label = Label.new()
	_time_label.text = NotLightL10n.text("ui.format.media_time_pair") % [NotLightL10n.text("ui.format.time_zero"), NotLightL10n.text("ui.format.time_zero")]
	_time_label.theme_type_variation = "CaptionStrongLabel"
	_time_label.custom_minimum_size = Vector2(128.0, 0.0)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	seek_row.add_child(_time_label)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 7)
	controls.add_child(buttons)

	var rewind: Button = Button.new()
	rewind.text = NotLightL10n.text("ui.format.rewind_seconds") % 10
	NotLightL10n.bind_tooltip(rewind, "runtime.ui.video_player_overlay.216589fca9")
	rewind.theme_type_variation = "GhostButton"
	rewind.pressed.connect(func() -> void: _skip(-10.0))
	buttons.add_child(rewind)

	_play_button = Button.new()
	_play_button.text = "▶"
	NotLightL10n.bind_tooltip(_play_button, "runtime.ui.video_player_overlay.96e2bf847b")
	_play_button.theme_type_variation = "PrimaryButton"
	_play_button.custom_minimum_size = Vector2(58.0, 38.0)
	_play_button.pressed.connect(_toggle_play)
	buttons.add_child(_play_button)

	var forward: Button = Button.new()
	forward.text = NotLightL10n.text("ui.format.forward_seconds") % 10
	NotLightL10n.bind_tooltip(forward, "runtime.ui.video_player_overlay.b1ad7a00e2")
	forward.theme_type_variation = "GhostButton"
	forward.pressed.connect(func() -> void: _skip(10.0))
	buttons.add_child(forward)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)

	_mute_button = Button.new()
	NotLightL10n.bind_text(_mute_button, "audio.player.sound")
	NotLightL10n.bind_tooltip(_mute_button, "runtime.ui.video_player_overlay.779d54ee2c")
	_mute_button.theme_type_variation = "GhostButton"
	_mute_button.pressed.connect(_toggle_mute)
	buttons.add_child(_mute_button)

	_volume_slider = HSlider.new()
	_volume_slider.scrollable = false
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.01
	_volume_slider.value = _remembered_volume
	_volume_slider.custom_minimum_size = Vector2(110.0, 24.0)
	_volume_slider.value_changed.connect(_on_volume_changed)
	buttons.add_child(_volume_slider)

	_loop_button = Button.new()
	NotLightL10n.bind_text(_loop_button, "runtime.ui.video_player_overlay.68c00cebb6")
	_loop_button.theme_type_variation = "GhostButton"
	_loop_button.pressed.connect(_toggle_loop)
	buttons.add_child(_loop_button)

	var fullscreen: Button = Button.new()
	fullscreen.text = "⛶"
	NotLightL10n.bind_tooltip(fullscreen, "runtime.ui.video_player_overlay.a16478c054")
	fullscreen.theme_type_variation = "IconButton"
	fullscreen.custom_minimum_size = Vector2(40.0, 38.0)
	fullscreen.pressed.connect(_toggle_fullscreen)
	buttons.add_child(fullscreen)

	var optimization_panel: PanelContainer = PanelContainer.new()
	optimization_panel.theme_type_variation = "SettingsInfoPanel"
	root.add_child(optimization_panel)
	var optimization_root: VBoxContainer = VBoxContainer.new()
	optimization_root.add_theme_constant_override("separation", 7)
	optimization_panel.add_child(optimization_root)

	var optimize_row: HBoxContainer = HBoxContainer.new()
	optimize_row.add_theme_constant_override("separation", 8)
	optimization_root.add_child(optimize_row)
	var optimize_text: VBoxContainer = VBoxContainer.new()
	optimize_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	optimize_row.add_child(optimize_text)
	var optimize_title: Label = Label.new()
	NotLightL10n.bind_text(optimize_title, "runtime.ui.video_player_overlay.78798d3206")
	optimize_title.theme_type_variation = "SectionLabel"
	optimize_text.add_child(optimize_title)
	_source_info_label = Label.new()
	NotLightL10n.bind_text(_source_info_label, "runtime.ui.video_player_overlay.454256820e")
	_source_info_label.theme_type_variation = "CaptionLabel"
	optimize_text.add_child(_source_info_label)

	_profile_option = OptionButton.new()
	_profile_option.theme_type_variation = "SettingsOptionButton"
	_profile_option.add_item(NotLightL10n.text("common.auto"))
	_profile_option.set_item_metadata(0, "auto")
	_profile_option.add_item(NotLightL10n.text("runtime.ui.video_player_overlay.fa7e315bc4"))
	_profile_option.set_item_metadata(1, "quality")
	_profile_option.add_item(NotLightL10n.text("settings.storage.balanced"))
	_profile_option.set_item_metadata(2, "balanced")
	_profile_option.add_item(NotLightL10n.text("runtime.ui.video_player_overlay.766e7cabf7"))
	_profile_option.set_item_metadata(3, "small")
	_profile_option.select(0)
	optimize_row.add_child(_profile_option)

	_optimize_button = Button.new()
	NotLightL10n.bind_text(_optimize_button, "runtime.ui.video_player_overlay.e55154ebb8")
	NotLightL10n.bind_tooltip(_optimize_button, "runtime.ui.video_player_overlay.3468f7d5b4")
	_optimize_button.theme_type_variation = "PrimaryButton"
	_optimize_button.pressed.connect(_start_optimization)
	optimize_row.add_child(_optimize_button)

	_cancel_optimize_button = Button.new()
	NotLightL10n.bind_text(_cancel_optimize_button, "common.cancel")
	_cancel_optimize_button.theme_type_variation = "GhostButton"
	_cancel_optimize_button.visible = false
	_cancel_optimize_button.pressed.connect(_cancel_optimization)
	optimize_row.add_child(_cancel_optimize_button)

	var progress_row: HBoxContainer = HBoxContainer.new()
	progress_row.add_theme_constant_override("separation", 10)
	optimization_root.add_child(progress_row)
	_optimization_progress = ProgressBar.new()
	_optimization_progress.min_value = 0.0
	_optimization_progress.max_value = 100.0
	_optimization_progress.value = 0.0
	_optimization_progress.show_percentage = false
	_optimization_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_optimization_progress.custom_minimum_size = Vector2(0.0, 8.0)
	progress_row.add_child(_optimization_progress)
	_optimization_label = Label.new()
	NotLightL10n.bind_text(_optimization_label, "runtime.ui.video_player_overlay.667a8e03d2")
	_optimization_label.theme_type_variation = "CaptionLabel"
	_optimization_label.custom_minimum_size = Vector2(250.0, 0.0)
	progress_row.add_child(_optimization_label)


func _load_stream(path: String) -> void:
	_video.stop()
	_video.stream = null
	_seek.value = 0.0
	_seek.max_value = maxf(duration, 1.0)
	NotLightL10n.bind_text(_state_label, "runtime.ui.video_player_overlay.8606ebee8e")
	if path.is_empty() or not FileAccess.file_exists(path):
		NotLightL10n.bind_text(_state_label, "runtime.ui.video_player_overlay.d8c705b0ae")
		return
	if not ClassDB.class_exists("FFmpegVideoStream"):
		NotLightL10n.bind_text(_state_label, "runtime.ui.video_board_player.62c77f9c1d")
		return
	var instance: Object = ClassDB.instantiate("FFmpegVideoStream")
	var stream_resource: VideoStream = instance as VideoStream
	if stream_resource == null:
		NotLightL10n.bind_text(_state_label, "runtime.ui.video_player_overlay.9149e258b0")
		return
	stream_resource.call("set_file", path)
	# Critical: set the file BEFORE assigning the stream. Assigning an empty
	# FFmpegVideoStream makes Godot call instantiate_playback() with no file.
	_video.stream = stream_resource
	call_deferred("_start_playback")


func _start_playback() -> void:
	if not visible or _video.stream == null:
		return
	_video.paused = false
	_video.play()
	_play_button.text = "Ⅱ"
	NotLightL10n.bind_text(_state_label, "runtime.ui.video_player_overlay.8c89c0a42a")


func _process(_delta: float) -> void:
	if not visible or _video == null or _video.stream == null:
		return
	if duration <= 0.0:
		var stream_length: float = _video.get_stream_length()
		if stream_length > 0.0:
			duration = stream_length
			_seek.max_value = duration
	var texture: Texture2D = _video.get_video_texture()
	if texture != null:
		var frame_size: Vector2 = texture.get_size()
		if frame_size.y > 0.0:
			_aspect.ratio = frame_size.x / frame_size.y
	if not _user_seeking:
		var position: float = maxf(0.0, _video.stream_position)
		if duration <= 0.0:
			_seek.max_value = maxf(1.0, position + 1.0)
		_seek.value = minf(position, _seek.max_value)
		_time_label.text = NotLightL10n.text("ui.format.media_time_pair") % [_format_time(position), _format_time(duration)]


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or event is not InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_ESCAPE:
			close_player()
		KEY_SPACE:
			_toggle_play()
		KEY_LEFT:
			_skip(-5.0)
		KEY_RIGHT:
			_skip(5.0)
		KEY_M:
			_toggle_mute()
		KEY_F:
			_toggle_fullscreen()
		_:
			return
	get_viewport().set_input_as_handled()


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			close_player()


func _on_stage_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.double_click:
			_toggle_fullscreen()
		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_toggle_play()


func _toggle_play() -> void:
	if _video.stream == null:
		return
	if not _video.is_playing():
		_video.paused = false
		_video.play()
		_play_button.text = "Ⅱ"
		NotLightL10n.bind_text(_state_label, "runtime.ui.video_player_overlay.8c89c0a42a")
	elif _video.paused:
		_video.paused = false
		_play_button.text = "Ⅱ"
		NotLightL10n.bind_text(_state_label, "runtime.ui.video_player_overlay.8c89c0a42a")
	else:
		_video.paused = true
		_play_button.text = "▶"
		NotLightL10n.bind_text(_state_label, "notes.embed.pause")


func _skip(seconds: float) -> void:
	if _video.stream == null:
		return
	var max_time: float = duration if duration > 0.0 else maxf(_seek.max_value, 1.0)
	var target: float = clampf(_video.stream_position + seconds, 0.0, max_time)
	_video.stream_position = target
	_seek.value = target


func _on_seek_drag_started() -> void:
	_user_seeking = true
	_resume_after_seek = _video.stream != null and _video.is_playing() and not _video.paused
	if _resume_after_seek:
		_video.paused = true


func _on_seek_drag_ended(_value_changed: bool) -> void:
	_user_seeking = false
	if _video.stream != null:
		_video.stream_position = _seek.value
		if _resume_after_seek:
			_video.paused = false
	_resume_after_seek = false


func _on_seek_value_changed(value: float) -> void:
	if _user_seeking:
		_time_label.text = NotLightL10n.text("ui.format.media_time_pair") % [_format_time(value), _format_time(duration)]


func _on_volume_changed(value: float) -> void:
	_remembered_volume = value
	_video.volume = value
	_mute_button.text = NotLightL10n.text("runtime.ui.video_player_overlay.812af98b94") if value <= 0.001 else NotLightL10n.text("audio.player.sound")


func _toggle_mute() -> void:
	if _volume_slider.value > 0.001:
		_remembered_volume = _volume_slider.value
		_volume_slider.value = 0.0
	else:
		_volume_slider.value = maxf(_remembered_volume, 0.35)


func _toggle_loop() -> void:
	_video.loop = not _video.loop
	_loop_button.text = NotLightL10n.text("runtime.ui.video_player_overlay.ff6d60ca32") if _video.loop else NotLightL10n.text("runtime.ui.video_player_overlay.68c00cebb6")


func _toggle_fullscreen() -> void:
	var current: int = DisplayServer.window_get_mode()
	if current == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(_window_mode_before_fullscreen)
	else:
		_window_mode_before_fullscreen = current
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _on_video_finished() -> void:
	_play_button.text = "▶"
	NotLightL10n.bind_text(_state_label, "runtime.ui.video_player_overlay.016bc923f7")
	_seek.value = 0.0


func _start_optimization() -> void:
	if media == null or asset_id.is_empty():
		return
	var metadata_value: Variant = _profile_option.get_item_metadata(_profile_option.selected)
	var profile: String = str(metadata_value)
	if media.enqueue_optimization(asset_id, profile):
		_optimize_button.disabled = true
		_cancel_optimize_button.visible = true
		NotLightL10n.bind_text(_optimization_label, "runtime.ui.video_player_overlay.dba97959c1")


func _cancel_optimization() -> void:
	if media != null and not asset_id.is_empty():
		media.cancel(asset_id)


func _on_optimization_started(changed_asset_id: String) -> void:
	if changed_asset_id != asset_id:
		return
	_optimize_button.disabled = true
	_cancel_optimize_button.visible = true
	_optimization_progress.value = 0.0
	NotLightL10n.bind_text(_optimization_label, "audio.status.preparing")


func _on_optimization_progress(changed_asset_id: String, progress: float, message: String) -> void:
	if changed_asset_id != asset_id:
		return
	_optimization_progress.value = progress * 100.0
	_optimization_label.text = message


func _on_optimization_completed(changed_asset_id: String, _optimized_path: String, saved_bytes: int) -> void:
	if changed_asset_id != asset_id:
		return
	_optimize_button.disabled = false
	_cancel_optimize_button.visible = false
	_optimization_progress.value = 100.0
	_optimization_label.text = NotLightL10n.text("runtime.ui.video_player_overlay.e148162956") % _format_bytes(saved_bytes)
	var metadata: Dictionary = media.get_metadata(asset_id, true)
	_refresh_source_info(metadata)
	# Reload from the optimized variant while preserving the current position.
	var position: float = _video.stream_position if _video.stream != null else 0.0
	_load_stream(media.resolve_playback_path(asset_id))
	if position > 0.0:
		call_deferred("_seek_after_reload", position)


func _seek_after_reload(position: float) -> void:
	if _video.stream != null:
		_video.stream_position = clampf(position, 0.0, duration if duration > 0.0 else position)


func _on_optimization_failed(changed_asset_id: String, message: String) -> void:
	if changed_asset_id != asset_id:
		return
	_optimize_button.disabled = false
	_cancel_optimize_button.visible = false
	_optimization_progress.value = 0.0
	_optimization_label.text = message


func _refresh_source_info(metadata: Dictionary) -> void:
	var dimensions: String = "%d×%d" % [int(metadata.get("width", 0)), int(metadata.get("height", 0))]
	var codec: String = str(metadata.get("video_codec", "")).to_upper()
	var fps: float = float(metadata.get("fps", 0.0))
	var original_size: int = int(metadata.get("source_size", metadata.get("size", 0)))
	var optimized_size: int = int(metadata.get("optimized_size", 0))
	var text: String = NotLightL10n.text("ui.format.video_source_info") % [
		dimensions,
		codec if not codec.is_empty() else "VIDEO",
		fps,
		_format_bytes(original_size),
	]
	if optimized_size > 0:
		text += NotLightL10n.text("ui.format.arrow_target") % _format_bytes(optimized_size)
	_source_info_label.text = text


func _refresh_optimization_state(metadata: Dictionary) -> void:
	var optimized_size: int = int(metadata.get("optimized_size", 0))
	_optimization_progress.value = 0.0
	var tools_ready: bool = media != null and media.tools_available()
	var busy: bool = tools_ready and media.is_optimizing(asset_id)
	_optimize_button.disabled = not tools_ready or busy
	_cancel_optimize_button.visible = busy
	if not tools_ready:
		NotLightL10n.bind_text(_optimization_label, "runtime.ui.video_player_overlay.defd6a8f0e")
		return
	if optimized_size > 0:
		var source_size: int = int(metadata.get("source_size", metadata.get("size", 0)))
		_optimization_label.text = NotLightL10n.text("runtime.ui.video_player_overlay.46d9b90815") % _format_bytes(maxi(0, source_size - optimized_size))
	else:
		NotLightL10n.bind_text(_optimization_label, "runtime.ui.video_player_overlay.667a8e03d2")


func _format_time(seconds: float) -> String:
	var total: int = maxi(0, int(seconds))
	var hours: int = total / 3600
	var minutes: int = (total % 3600) / 60
	var secs: int = total % 60
	if hours > 0:
		return NotLightL10n.text("ui.format.time_hms") % [hours, minutes, secs]
	return NotLightL10n.text("ui.format.time_ms") % [minutes, secs]


func _format_bytes(byte_count: int) -> String:
	var value: float = float(maxi(0, byte_count))
	if value < 1024.0:
		return NotLightL10n.text("runtime.ui.video_player_overlay.900cf07d0d") % int(value)
	value /= 1024.0
	if value < 1024.0:
		return NotLightL10n.text("runtime.ui.video_player_overlay.7a76f539cd") % value
	value /= 1024.0
	if value < 1024.0:
		return NotLightL10n.text("runtime.ui.video_player_overlay.93eb0c0182") % value
	value /= 1024.0
	return NotLightL10n.text("runtime.ui.video_player_overlay.f4aee12c68") % value
