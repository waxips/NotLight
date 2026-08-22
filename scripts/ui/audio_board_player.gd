# SPDX-License-Identifier: GPL-3.0-or-later
class_name AudioBoardPlayer
extends PanelContainer

signal close_requested(entity_id: int)
signal flags_changed(entity_id: int, flags: int)
signal message_requested(message: String)

var entity_id: int = 0
var asset_id: String = ""
var media: AudioMediaService
var duration: float = 0.0

var _player: AudioStreamPlayer
var _content_margin: MarginContainer
var _waveform: AudioWaveformView
var _header: HBoxContainer
var _title_label: Label
var _status_label: Label
var _controls: HBoxContainer
var _play_button: Button
var _seek: HSlider
var _time_label: Label
var _mute_button: Button
var _volume_slider: HSlider
var _loop_button: Button
var _user_seeking: bool = false
var _resume_after_seek: bool = false
var _paused_position: float = 0.0
var _pending_seek_position: float = -1.0
var _pending_seek_deadline_msec: int = 0
var _remembered_volume: float = 0.82
var _flags: int = 0
var _autoplay_when_ready: bool = false
var _layout_mode: int = -1
var _layout_signature: int = -1
var _inline_screen_size: Vector2 = Vector2(420.0, 128.0)

const LAYOUT_TINY: int = 0
const LAYOUT_COMPACT: int = 1
const LAYOUT_FULL: int = 2


func _ready() -> void:
	theme_type_variation = "AudioPlayerCardPanel"
	clip_contents = true
	# Match the video-player interaction model: the media surface itself lets
	# pointer input reach NativeBoardView, so dragging the active audio card moves
	# the DOD entity. Only actual player controls intercept pointer events.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	set_process(true)


func configure(
	new_entity_id: int,
	new_asset_id: String,
	display_name: String,
	audio_media: AudioMediaService,
	initial_flags: int = 0
) -> void:
	entity_id = new_entity_id
	asset_id = new_asset_id
	media = audio_media
	_flags = initial_flags
	set_display_name(display_name)
	_apply_flags()
	if media == null:
		_set_status(NotLightL10n.text("audio.status.service_unavailable"))
		return
	if not media.playback_ready.is_connected(_on_playback_ready):
		media.playback_ready.connect(_on_playback_ready)
	if not media.waveform_ready.is_connected(_on_waveform_ready):
		media.waveform_ready.connect(_on_waveform_ready)
	if not media.preparation_failed.is_connected(_on_preparation_failed):
		media.preparation_failed.connect(_on_preparation_failed)
	if not media.playback_variant_changed.is_connected(_on_playback_variant_changed):
		media.playback_variant_changed.connect(_on_playback_variant_changed)
	var metadata: Dictionary = media.ensure_asset(asset_id)
	duration = maxf(0.0, float(metadata.get("duration", 0.0)))
	_seek.max_value = maxf(duration, 1.0)
	_refresh_waveform()
	_try_load_stream(true)


func set_display_name(display_name: String) -> void:
	if _title_label == null:
		return
	var clean_name: String = display_name.strip_edges()
	_title_label.text = clean_name if not clean_name.is_empty() else NotLightL10n.text("board.asset.audio")
	_title_label.tooltip_text = _title_label.text


func set_inline_screen_size(screen_size: Vector2) -> void:
	_inline_screen_size = Vector2(maxf(1.0, screen_size.x), maxf(1.0, screen_size.y))
	var next_mode: int = LAYOUT_FULL
	if _inline_screen_size.x < 112.0 or _inline_screen_size.y < 46.0:
		next_mode = LAYOUT_TINY
	elif _inline_screen_size.x < 320.0 or _inline_screen_size.y < 104.0:
		next_mode = LAYOUT_COMPACT
	var next_signature: int = _responsive_layout_signature(_inline_screen_size, next_mode)
	if next_signature == _layout_signature:
		return
	_layout_mode = next_mode
	_layout_signature = next_signature
	_apply_responsive_layout()


func _responsive_layout_signature(screen_size: Vector2, mode: int) -> int:
	var signature: int = mode
	if screen_size.x >= 150.0:
		signature |= 1 << 3
	if screen_size.x >= 225.0:
		signature |= 1 << 4
	if screen_size.x >= 330.0:
		signature |= 1 << 5
	if screen_size.x >= 365.0:
		signature |= 1 << 6
	if screen_size.x >= 420.0:
		signature |= 1 << 7
	if screen_size.x >= 480.0:
		signature |= 1 << 8
	return signature


func toggle_play() -> void:
	if _player == null or _player.stream == null:
		_try_load_stream(true)
		return
	if _player.stream_paused:
		# AudioStreamPlayer.playing is not a reliable paused-state discriminator: a
		# paused stream can report playing=false while the playback object is still
		# alive. Resume the existing playback instead of calling play(), which would
		# restart the track from zero. Re-apply a pending paused seek immediately
		# before resume so a backend that reports its old position for a few frames
		# cannot pull the timeline back.
		if _player.has_stream_playback():
			if _pending_seek_position >= 0.0:
				_player.seek(_pending_seek_position)
			_player.stream_paused = false
		else:
			_player.play(_normalized_resume_position())
			_player.stream_paused = false
	elif _player.has_stream_playback():
		_paused_position = _current_playback_position()
		_player.stream_paused = true
	else:
		_player.play(_normalized_resume_position())
		_player.stream_paused = false
	_refresh_play_icon()
	_update_waveform_progress()


func shutdown() -> void:
	if _player != null:
		_player.stop()
		_player.stream = null
	queue_free()


func _build_ui() -> void:
	_content_margin = MarginContainer.new()
	_content_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content_margin)

	var stack: VBoxContainer = VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 5)
	_content_margin.add_child(stack)

	_header = HBoxContainer.new()
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_theme_constant_override("separation", 6)
	stack.add_child(_header)

	var media_mark: Label = Label.new()
	media_mark.text = "♪"
	media_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	media_mark.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
	media_mark.custom_minimum_size = Vector2(22.0, 28.0)
	media_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	media_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header.add_child(media_mark)

	_title_label = Label.new()
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.theme_type_variation = "CaptionStrongLabel"
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header.add_child(_title_label)

	_status_label = Label.new()
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.theme_type_variation = "CaptionLabel"
	_status_label.visible = false
	_header.add_child(_status_label)

	var close_button: Button = Button.new()
	close_button.icon = load("res://assets/icons/close.svg") as Texture2D
	NotLightL10n.bind_tooltip(close_button, "audio.player.close")
	close_button.theme_type_variation = "IconButton"
	close_button.custom_minimum_size = Vector2(34.0, 30.0)
	close_button.expand_icon = true
	close_button.add_theme_constant_override("icon_max_width", 15)
	close_button.pressed.connect(func() -> void: close_requested.emit(entity_id))
	_header.add_child(close_button)

	_waveform = AudioWaveformView.new()
	_waveform.custom_minimum_size = Vector2(80.0, 42.0)
	_waveform.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_waveform.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(_waveform)

	_controls = HBoxContainer.new()
	# The container itself is transparent to board dragging; the Button/Slider
	# children keep their default mouse handling, so only real controls capture
	# pointer input and the gaps remain usable as a drag surface.
	_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls.add_theme_constant_override("separation", 6)
	stack.add_child(_controls)

	_play_button = Button.new()
	_play_button.text = "▶"
	NotLightL10n.bind_tooltip(_play_button, "audio.player.play_pause")
	_play_button.theme_type_variation = "PrimaryButton"
	_play_button.custom_minimum_size = Vector2(42.0, 34.0)
	_play_button.pressed.connect(toggle_play)
	_controls.add_child(_play_button)

	_seek = HSlider.new()
	_seek.scrollable = false
	_seek.min_value = 0.0
	_seek.max_value = 1.0
	_seek.step = 0.01
	_seek.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seek.custom_minimum_size = Vector2(76.0, 26.0)
	_seek.drag_started.connect(_on_seek_started)
	_seek.drag_ended.connect(_on_seek_ended)
	_seek.value_changed.connect(_on_seek_changed)
	_controls.add_child(_seek)

	_time_label = Label.new()
	_time_label.text = NotLightL10n.text("ui.format.time_zero")
	_time_label.theme_type_variation = "CaptionLabel"
	_time_label.custom_minimum_size = Vector2(84.0, 0.0)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_controls.add_child(_time_label)

	_mute_button = Button.new()
	_mute_button.text = "♪"
	NotLightL10n.bind_tooltip(_mute_button, "audio.player.sound")
	_mute_button.theme_type_variation = "IconButton"
	_mute_button.custom_minimum_size = Vector2(36.0, 34.0)
	_mute_button.pressed.connect(_toggle_mute)
	_controls.add_child(_mute_button)

	_volume_slider = HSlider.new()
	_volume_slider.scrollable = false
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.01
	_volume_slider.value = _remembered_volume
	NotLightL10n.bind_tooltip(_volume_slider, "audio.player.volume")
	_volume_slider.custom_minimum_size = Vector2(80.0, 26.0)
	_volume_slider.value_changed.connect(_on_volume_changed)
	_controls.add_child(_volume_slider)

	_loop_button = Button.new()
	_loop_button.text = "↻"
	NotLightL10n.bind_tooltip(_loop_button, "audio.player.loop")
	_loop_button.toggle_mode = true
	_loop_button.theme_type_variation = "IconButton"
	_loop_button.custom_minimum_size = Vector2(36.0, 34.0)
	_loop_button.toggled.connect(_on_loop_toggled)
	_controls.add_child(_loop_button)

	_player = AudioStreamPlayer.new()
	_player.name = "AudioPlayback"
	_player.finished.connect(_on_finished)
	add_child(_player)
	_player.add_to_group(AppAudioService.FOREGROUND_MEDIA_GROUP)


func _process(_delta: float) -> void:
	if _player == null or _player.stream == null:
		if _waveform != null and is_visible_in_tree():
			_waveform.set_playback_progress(0.0, false)
		return
	# Playback intentionally keeps running while an active card is outside the
	# viewport, but there is no reason to format labels or redraw waveform UI that
	# cannot be seen. The bounded player pool therefore remains cheap offscreen.
	if not is_visible_in_tree():
		return
	if duration <= 0.0:
		duration = maxf(0.0, _player.stream.get_length())
		_seek.max_value = maxf(duration, 1.0)
	if not _user_seeking:
		var position_value: float = _display_playback_position()
		if _seek.is_visible_in_tree():
			_seek.set_value_no_signal(clampf(position_value, 0.0, maxf(_seek.max_value, 1.0)))
		if _time_label.is_visible_in_tree():
			_time_label.text = NotLightL10n.text("ui.format.media_time_pair") % [_format_time(position_value), _format_time(duration)]
	_update_waveform_progress()
	if _play_button.is_visible_in_tree():
		_refresh_play_icon()


func _update_waveform_progress() -> void:
	if _waveform == null:
		return
	var position_value: float = _seek.value if _user_seeking else _display_playback_position()
	var progress: float = position_value / duration if duration > 0.001 else 0.0
	var playing: bool = _player != null and _player.has_stream_playback() and not _player.stream_paused
	_waveform.set_playback_progress(progress, playing)


func _try_load_stream(autoplay: bool) -> void:
	if media == null:
		return
	if autoplay:
		_autoplay_when_ready = true
	var stream: AudioStream = media.load_stream(asset_id)
	if stream == null:
		_set_status(NotLightL10n.text("audio.status.preparing"))
		return
	_player.stop()
	_player.stream = stream
	_player.stream_paused = false
	_paused_position = 0.0
	_pending_seek_position = -1.0
	_pending_seek_deadline_msec = 0
	if duration <= 0.0:
		duration = maxf(0.0, stream.get_length())
		_seek.max_value = maxf(duration, 1.0)
	_set_status("")
	if autoplay or _autoplay_when_ready:
		_player.play(_normalized_resume_position())
	_autoplay_when_ready = false
	_refresh_play_icon()
	_update_waveform_progress()


func _refresh_waveform() -> void:
	if media == null or _waveform == null:
		return
	_waveform.set_waveform(media.get_waveform(asset_id))


func _apply_responsive_layout() -> void:
	if _header == null or _waveform == null or _controls == null:
		return
	var width: float = _inline_screen_size.x
	var content_margin: int = 8
	if _layout_mode == LAYOUT_TINY:
		content_margin = 0
	elif _layout_mode == LAYOUT_COMPACT:
		content_margin = 4
	if _content_margin != null:
		_content_margin.add_theme_constant_override("margin_left", content_margin)
		_content_margin.add_theme_constant_override("margin_top", content_margin)
		_content_margin.add_theme_constant_override("margin_right", content_margin)
		_content_margin.add_theme_constant_override("margin_bottom", content_margin)
	match _layout_mode:
		LAYOUT_TINY:
			_header.visible = false
			_controls.visible = false
			_waveform.visible = true
			_waveform.custom_minimum_size = Vector2.ZERO
			_waveform.set_compact(true)
		LAYOUT_COMPACT:
			_header.visible = false
			_controls.visible = true
			_waveform.visible = true
			_waveform.custom_minimum_size = Vector2(40.0, 22.0)
			_waveform.set_compact(true)
			_seek.visible = width >= 150.0
			_time_label.visible = false
			_mute_button.visible = width >= 225.0
			_volume_slider.visible = false
			_loop_button.visible = false
		_:
			_header.visible = true
			_controls.visible = true
			_waveform.visible = true
			_waveform.custom_minimum_size = Vector2(80.0, 42.0)
			_waveform.set_compact(false)
			_seek.visible = true
			_time_label.visible = width >= 330.0
			_mute_button.visible = width >= 365.0
			_volume_slider.visible = width >= 480.0
			_loop_button.visible = width >= 420.0


func _apply_flags() -> void:
	var muted: bool = (_flags & AudioStore.FLAG_MUTED) != 0
	var looped: bool = (_flags & AudioStore.FLAG_LOOP) != 0
	if _loop_button != null:
		_loop_button.set_pressed_no_signal(looped)
	if _player != null:
		_player.volume_db = -80.0 if muted else linear_to_db(maxf(_remembered_volume, 0.001))
	if _volume_slider != null:
		_volume_slider.set_value_no_signal(0.0 if muted else _remembered_volume)
	if _mute_button != null:
		_mute_button.text = "×♪" if muted else "♪"


func _emit_flags() -> void:
	flags_changed.emit(entity_id, _flags)


func _toggle_mute() -> void:
	var muted: bool = (_flags & AudioStore.FLAG_MUTED) != 0
	if muted:
		_flags &= ~AudioStore.FLAG_MUTED
		_player.volume_db = linear_to_db(maxf(_remembered_volume, 0.01))
		_volume_slider.set_value_no_signal(_remembered_volume)
	else:
		_flags |= AudioStore.FLAG_MUTED
		_player.volume_db = -80.0
		_volume_slider.set_value_no_signal(0.0)
	_apply_flags()
	_emit_flags()


func _on_volume_changed(value: float) -> void:
	var safe: float = clampf(value, 0.0, 1.0)
	if safe > 0.001:
		_remembered_volume = safe
		_flags &= ~AudioStore.FLAG_MUTED
	else:
		_flags |= AudioStore.FLAG_MUTED
	_player.volume_db = -80.0 if safe <= 0.001 else linear_to_db(safe)
	_mute_button.text = "×♪" if safe <= 0.001 else "♪"
	_emit_flags()


func _on_loop_toggled(enabled: bool) -> void:
	if enabled:
		_flags |= AudioStore.FLAG_LOOP
	else:
		_flags &= ~AudioStore.FLAG_LOOP
	_emit_flags()


func _on_seek_started() -> void:
	if _player == null or _player.stream == null:
		return
	_user_seeking = true
	_resume_after_seek = _player.has_stream_playback() and not _player.stream_paused
	if _player.has_stream_playback():
		_paused_position = _current_playback_position()
		_player.stream_paused = true


func _on_seek_ended(_changed: bool) -> void:
	if _player == null or _player.stream == null:
		_user_seeking = false
		_resume_after_seek = false
		return
	var target: float = clampf(_seek.value, 0.0, maxf(duration, 0.0))
	_user_seeking = false
	_apply_seek_target(target, _resume_after_seek)
	_resume_after_seek = false
	_update_waveform_progress()


func _on_seek_changed(value: float) -> void:
	var target: float = clampf(value, 0.0, maxf(duration, 0.0))
	if _user_seeking:
		_paused_position = target
		if _time_label.is_visible_in_tree():
			_time_label.text = NotLightL10n.text("ui.format.media_time_pair") % [_format_time(target), _format_time(duration)]
		_update_waveform_progress()
		return
	# Slider.value_changed is user-originated here because every timeline refresh
	# uses set_value_no_signal(). This also covers track clicks and keyboard seek,
	# which do not necessarily produce Slider.drag_started/drag_ended on all input
	# paths. Preserve whether the stream was playing or paused across the seek.
	if _player != null and _player.stream != null:
		var resume_after: bool = _player.has_stream_playback() and not _player.stream_paused
		_apply_seek_target(target, resume_after)
		_update_waveform_progress()


func _apply_seek_target(target: float, resume_after: bool) -> void:
	_paused_position = target
	_pending_seek_position = target
	_pending_seek_deadline_msec = Time.get_ticks_msec() + 600
	if _player.has_stream_playback():
		_player.seek(target)
		_player.stream_paused = not resume_after
	elif resume_after:
		_player.play(target)
		_player.stream_paused = false
	# When the player is stopped, keep the target as a logical resume position.
	# Calling seek() here would be a no-op according to AudioStreamPlayer's API.


func _current_playback_position() -> float:
	if _player == null or _player.stream == null or not _player.has_stream_playback():
		return clampf(_paused_position, 0.0, maxf(duration, 0.0))
	return clampf(_player.get_playback_position(), 0.0, maxf(duration, 0.0))


func _display_playback_position() -> float:
	if _pending_seek_position >= 0.0:
		var actual: float = _current_playback_position()
		var now_msec: int = Time.get_ticks_msec()
		if absf(actual - _pending_seek_position) <= 0.35:
			_paused_position = actual
			_pending_seek_position = -1.0
			_pending_seek_deadline_msec = 0
		elif now_msec >= _pending_seek_deadline_msec and _player != null and _player.has_stream_playback() and not _player.stream_paused:
			# Once playback is running, the backend position is authoritative after the
			# grace window. While paused, however, keep the user's target stable rather
			# than letting a stale decoder position visually snap the slider backwards.
			_paused_position = actual
			_pending_seek_position = -1.0
			_pending_seek_deadline_msec = 0
		else:
			return _pending_seek_position
	if _player != null and _player.has_stream_playback():
		_paused_position = _current_playback_position()
	return clampf(_paused_position, 0.0, maxf(duration, 0.0))


func _normalized_resume_position() -> float:
	var safe_duration: float = maxf(duration, 0.0)
	if safe_duration <= 0.001:
		return maxf(0.0, _paused_position)
	if _paused_position >= safe_duration - 0.05:
		_paused_position = 0.0
	return clampf(_paused_position, 0.0, safe_duration)


func _on_finished() -> void:
	_paused_position = 0.0
	_pending_seek_position = -1.0
	_pending_seek_deadline_msec = 0
	_seek.set_value_no_signal(0.0)
	if (_flags & AudioStore.FLAG_LOOP) != 0:
		_player.play(0.0)
	_refresh_play_icon()
	_update_waveform_progress()


func _on_playback_ready(ready_asset_id: String, _path: String) -> void:
	if ready_asset_id == asset_id and (_player == null or _player.stream == null):
		_try_load_stream(_autoplay_when_ready)


func _on_waveform_ready(ready_asset_id: String) -> void:
	if ready_asset_id == asset_id:
		_refresh_waveform()


func _on_playback_variant_changed(changed_asset_id: String, _path: String, _variant_name: String) -> void:
	if changed_asset_id != asset_id or media == null or _player == null:
		return
	var had_playback: bool = _player.has_stream_playback()
	var was_paused: bool = _player.stream_paused
	var resume_position: float = _display_playback_position()
	var replacement: AudioStream = media.load_stream(asset_id)
	if replacement == null:
		_set_status(NotLightL10n.text("audio.status.preparing"))
		return
	_player.stop()
	_player.stream = replacement
	_player.stream_paused = false
	_paused_position = clampf(resume_position, 0.0, maxf(duration, 0.0))
	_pending_seek_position = -1.0
	_pending_seek_deadline_msec = 0
	if had_playback:
		_player.play(_normalized_resume_position())
		_player.stream_paused = was_paused
	_set_status("")
	_refresh_play_icon()
	_update_waveform_progress()


func _on_preparation_failed(failed_asset_id: String, message: String) -> void:
	if failed_asset_id != asset_id:
		return
	_set_status(NotLightL10n.text("audio.status.unavailable"))
	message_requested.emit(message)


func _set_status(message: String) -> void:
	if _status_label == null:
		return
	_status_label.text = message
	_status_label.visible = not message.is_empty()


func _refresh_play_icon() -> void:
	if _play_button != null:
		var actively_playing: bool = _player != null and _player.has_stream_playback() and not _player.stream_paused
		_play_button.text = "Ⅱ" if actively_playing else "▶"


func _format_time(seconds: float) -> String:
	var total: int = maxi(0, int(round(seconds)))
	var hours: int = int(total / 3600)
	var minutes: int = int((total % 3600) / 60)
	var secs: int = total % 60
	if hours > 0:
		return NotLightL10n.text("ui.format.time_hms") % [hours, minutes, secs]
	return NotLightL10n.text("ui.format.time_ms") % [minutes, secs]
