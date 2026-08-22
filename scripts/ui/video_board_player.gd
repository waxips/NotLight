# SPDX-License-Identifier: GPL-3.0-or-later
class_name VideoBoardPlayer
extends PanelContainer

signal close_requested(entity_id: int)
signal expand_requested(entity_id: int)
signal message_requested(message: String)

const MENU_OPTIMIZE_AUTO: int = 10
const MENU_USE_ORIGINAL: int = 20
const MENU_USE_OPTIMIZED: int = 21
const MENU_DELETE_ORIGINAL: int = 30
const MENU_DELETE_OPTIMIZED: int = 31

var entity_id: int = 0
var asset_id: String = ""
var media: VideoMediaService
var duration: float = 0.0
var expanded: bool = false

var _content_margin: MarginContainer
var _stage: Control
var _aspect: AspectRatioContainer
var _video: VideoStreamPlayer
var _header: PanelContainer
var _controls: PanelContainer
var _title_label: Label
var _status_label: Label
var _expand_button: Button
var _play_button: Button
var _rewind_button: Button
var _forward_button: Button
var _seek: HSlider
var _time_label: Label
var _mute_button: Button
var _volume_slider: HSlider
var _loop_button: Button
var _menu_button: Button
var _menu: PopupMenu

var _video_aspect_ratio: float = 16.0 / 9.0
var _user_seeking: bool = false
var _resume_after_seek: bool = false
var _remembered_volume: float = 0.80
var _loaded_path: String = ""
var _inline_screen_size: Vector2 = Vector2(320.0, 180.0)
var _inline_layout_signature: int = -1


func _ready() -> void:
	theme_type_variation = "VideoPlayerCardPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	z_index = 0
	_build_ui()
	set_process(true)


func configure(
	new_entity_id: int,
	new_asset_id: String,
	display_name: String,
	video_media: VideoMediaService
) -> void:
	entity_id = new_entity_id
	asset_id = new_asset_id
	media = video_media
	set_display_name(display_name)
	if media == null:
		NotLightL10n.bind_text(_status_label, "runtime.ui.video_board_player.16af04768b")
		_status_label.visible = true
		return
	if not media.playback_variant_changed.is_connected(_on_playback_variant_changed):
		media.playback_variant_changed.connect(_on_playback_variant_changed)
	if not media.optimization_progress.is_connected(_on_optimization_progress):
		media.optimization_progress.connect(_on_optimization_progress)
	if not media.optimization_failed.is_connected(_on_optimization_failed):
		media.optimization_failed.connect(_on_optimization_failed)
	var metadata: Dictionary = media.ensure_asset(asset_id)
	_apply_metadata(metadata)
	_refresh_variant_menu()
	_load_stream(media.resolve_playback_path(asset_id), true)


func set_display_name(display_name: String) -> void:
	if _title_label == null:
		return
	var clean_name: String = display_name.strip_edges()
	_title_label.text = clean_name if not clean_name.is_empty() else NotLightL10n.text("asset.kind.video")
	_title_label.tooltip_text = _title_label.text


func video_aspect_ratio() -> float:
	return clampf(_video_aspect_ratio, 0.20, 5.0)


func shutdown() -> void:
	if _video != null:
		_video.stop()
		_video.stream = null
	queue_free()


func set_inline_screen_size(screen_size: Vector2) -> void:
	var next_size: Vector2 = Vector2(maxf(1.0, screen_size.x), maxf(1.0, screen_size.y))
	_inline_screen_size = next_size
	var next_signature: int = _responsive_layout_signature(next_size)
	if next_signature == _inline_layout_signature:
		return
	_inline_layout_signature = next_signature
	if not expanded and _stage != null:
		_stage.custom_minimum_size = Vector2.ZERO if next_signature == 0 else Vector2(180.0, 110.0)
	_update_responsive_controls()


func _responsive_layout_signature(screen_size: Vector2) -> int:
	var width: float = screen_size.x
	var height: float = screen_size.y
	if width < 320.0 or height < 170.0:
		return 0
	var signature: int = 1
	if width >= 420.0:
		signature |= 1 << 1
	if height >= 220.0:
		signature |= 1 << 2
	if width >= 350.0:
		signature |= 1 << 3
	if width >= 360.0:
		signature |= 1 << 4
	if width >= 390.0:
		signature |= 1 << 5
	if width >= 500.0:
		signature |= 1 << 6
	if width >= 570.0:
		signature |= 1 << 7
	if width >= 680.0:
		signature |= 1 << 8
	return signature


func set_expanded(value: bool) -> void:
	expanded = value
	if _stage != null:
		_stage.custom_minimum_size = Vector2(180.0, 110.0) if expanded else (Vector2.ZERO if _inline_screen_size.x < 320.0 or _inline_screen_size.y < 170.0 else Vector2(180.0, 110.0))
	theme_type_variation = "VideoExpandedPlayerPanel" if expanded else "VideoPlayerCardPanel"
	clip_contents = not expanded
	if _content_margin != null:
		var margin_value: int = 10 if expanded else 0
		_content_margin.add_theme_constant_override("margin_left", margin_value)
		_content_margin.add_theme_constant_override("margin_top", margin_value)
		_content_margin.add_theme_constant_override("margin_right", margin_value)
		_content_margin.add_theme_constant_override("margin_bottom", margin_value)
	if _expand_button != null:
		_expand_button.text = "↙" if expanded else "↗"
		_expand_button.tooltip_text = NotLightL10n.text("runtime.ui.video_board_player.04ef8b2718") if expanded else NotLightL10n.text("runtime.ui.video_board_player.a903ea1045")
	if _header != null:
		_header.offset_left = 8.0 if expanded else 7.0
		_header.offset_top = 8.0 if expanded else 7.0
		_header.offset_right = -8.0 if expanded else -7.0
		_header.offset_bottom = 48.0 if expanded else 43.0
	if _controls != null:
		_controls.offset_left = 8.0 if expanded else 7.0
		_controls.offset_top = -60.0 if expanded else -57.0
		_controls.offset_right = -8.0 if expanded else -7.0
		_controls.offset_bottom = -8.0 if expanded else -7.0
	_update_responsive_controls()


func toggle_play() -> void:
	if _video == null or _video.stream == null:
		return
	if not _video.is_playing():
		_video.paused = false
		_video.play()
	elif _video.paused:
		_video.paused = false
	else:
		_video.paused = true
	_refresh_play_icon()


func _build_ui() -> void:
	_content_margin = MarginContainer.new()
	_content_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content_margin)

	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.custom_minimum_size = Vector2(180.0, 110.0)
	_content_margin.add_child(_stage)

	var viewport_panel: PanelContainer = PanelContainer.new()
	viewport_panel.theme_type_variation = "VideoViewportPanel"
	viewport_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(viewport_panel)

	_aspect = AspectRatioContainer.new()
	_aspect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_aspect.ratio = _video_aspect_ratio
	_aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	_aspect.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
	_aspect.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
	_aspect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_aspect)

	_video = VideoStreamPlayer.new()
	_video.expand = true
	_video.volume = _remembered_volume
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video.finished.connect(_on_finished)
	_aspect.add_child(_video)
	_video.add_to_group(AppAudioService.FOREGROUND_MEDIA_GROUP)

	_header = PanelContainer.new()
	_header.theme_type_variation = "VideoOverlayBar"
	_header.anchor_left = 0.0
	_header.anchor_top = 0.0
	_header.anchor_right = 1.0
	_header.anchor_bottom = 0.0
	_header.offset_left = 7.0
	_header.offset_top = 7.0
	_header.offset_right = -7.0
	_header.offset_bottom = 43.0
	_header.mouse_filter = Control.MOUSE_FILTER_PASS
	_stage.add_child(_header)

	var header_row: HBoxContainer = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 5)
	_header.add_child(header_row)

	var media_mark: Label = Label.new()
	media_mark.text = "▶"
	NotLightL10n.bind_tooltip(media_mark, "asset.kind.video")
	media_mark.theme_type_variation = "VideoOverlayMutedLabel"
	media_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	media_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	media_mark.custom_minimum_size = Vector2(22.0, 0.0)
	header_row.add_child(media_mark)

	_title_label = Label.new()
	_title_label.theme_type_variation = "VideoOverlayLabel"
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(_title_label)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.theme_type_variation = "VideoOverlayMutedLabel"
	_status_label.visible = false
	header_row.add_child(_status_label)

	_expand_button = Button.new()
	_expand_button.text = "↗"
	NotLightL10n.bind_tooltip(_expand_button, "runtime.ui.video_board_player.a903ea1045")
	_expand_button.theme_type_variation = "VideoOverlayButton"
	_expand_button.custom_minimum_size = Vector2(32.0, 28.0)
	_expand_button.pressed.connect(func() -> void: expand_requested.emit(entity_id))
	header_row.add_child(_expand_button)

	_menu_button = Button.new()
	_menu_button.text = "⋯"
	NotLightL10n.bind_tooltip(_menu_button, "runtime.ui.video_board_player.0032c755cf")
	_menu_button.theme_type_variation = "VideoOverlayButton"
	_menu_button.custom_minimum_size = Vector2(32.0, 28.0)
	_menu_button.pressed.connect(_open_menu)
	header_row.add_child(_menu_button)

	var close_button: Button = Button.new()
	close_button.text = "×"
	NotLightL10n.bind_tooltip(close_button, "runtime.ui.video_board_player.16c4eaf965")
	close_button.theme_type_variation = "VideoOverlayButton"
	close_button.custom_minimum_size = Vector2(32.0, 28.0)
	close_button.pressed.connect(func() -> void: close_requested.emit(entity_id))
	header_row.add_child(close_button)

	_controls = PanelContainer.new()
	_controls.theme_type_variation = "VideoOverlayBar"
	_controls.anchor_left = 0.0
	_controls.anchor_top = 1.0
	_controls.anchor_right = 1.0
	_controls.anchor_bottom = 1.0
	_controls.offset_left = 7.0
	_controls.offset_top = -57.0
	_controls.offset_right = -7.0
	_controls.offset_bottom = -7.0
	_controls.mouse_filter = Control.MOUSE_FILTER_PASS
	_stage.add_child(_controls)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_controls.add_child(row)

	_play_button = Button.new()
	_play_button.text = "▶"
	NotLightL10n.bind_tooltip(_play_button, "audio.player.play_pause")
	_play_button.theme_type_variation = "VideoOverlayPrimaryButton"
	_play_button.custom_minimum_size = Vector2(38.0, 34.0)
	_play_button.pressed.connect(toggle_play)
	row.add_child(_play_button)

	_rewind_button = Button.new()
	_rewind_button.text = NotLightL10n.text("ui.format.rewind_seconds_compact") % 10
	NotLightL10n.bind_tooltip(_rewind_button, "runtime.ui.video_board_player.5ef4412044")
	_rewind_button.theme_type_variation = "VideoOverlayButton"
	_rewind_button.custom_minimum_size = Vector2(42.0, 34.0)
	_rewind_button.pressed.connect(_seek_relative.bind(-10.0))
	row.add_child(_rewind_button)

	_forward_button = Button.new()
	_forward_button.text = "+10"
	NotLightL10n.bind_tooltip(_forward_button, "runtime.ui.video_board_player.c86f5666ca")
	_forward_button.theme_type_variation = "VideoOverlayButton"
	_forward_button.custom_minimum_size = Vector2(42.0, 34.0)
	_forward_button.pressed.connect(_seek_relative.bind(10.0))
	row.add_child(_forward_button)

	_seek = HSlider.new()
	_seek.scrollable = false
	_seek.min_value = 0.0
	_seek.max_value = 1.0
	_seek.step = 0.01
	_seek.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seek.custom_minimum_size = Vector2(70.0, 26.0)
	_seek.drag_started.connect(_on_seek_started)
	_seek.drag_ended.connect(_on_seek_ended)
	_seek.value_changed.connect(_on_seek_changed)
	row.add_child(_seek)

	_time_label = Label.new()
	_time_label.text = NotLightL10n.text("ui.format.time_zero")
	_time_label.theme_type_variation = "VideoOverlayLabel"
	_time_label.custom_minimum_size = Vector2(76.0, 0.0)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_time_label)

	_mute_button = Button.new()
	_mute_button.text = "♪"
	NotLightL10n.bind_tooltip(_mute_button, "audio.player.sound")
	_mute_button.theme_type_variation = "VideoOverlayButton"
	_mute_button.custom_minimum_size = Vector2(34.0, 34.0)
	_mute_button.pressed.connect(_toggle_mute)
	row.add_child(_mute_button)

	_volume_slider = HSlider.new()
	_volume_slider.scrollable = false
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.01
	_volume_slider.value = _remembered_volume
	NotLightL10n.bind_tooltip(_volume_slider, "audio.player.volume")
	_volume_slider.custom_minimum_size = Vector2(88.0, 26.0)
	_volume_slider.value_changed.connect(_on_volume_changed)
	row.add_child(_volume_slider)

	_loop_button = Button.new()
	_loop_button.text = "↻"
	NotLightL10n.bind_tooltip(_loop_button, "runtime.ui.video_board_player.c11523554b")
	_loop_button.toggle_mode = true
	_loop_button.theme_type_variation = "VideoOverlayButton"
	_loop_button.custom_minimum_size = Vector2(34.0, 34.0)
	_loop_button.toggled.connect(_on_loop_toggled)
	row.add_child(_loop_button)

	_menu = PopupMenu.new()
	_menu.add_item(NotLightL10n.text("runtime.ui.video_board_player.7d3055f392"), MENU_OPTIMIZE_AUTO)
	_menu.add_separator()
	_menu.add_radio_check_item(NotLightL10n.text("pdf.menu.use_original"), MENU_USE_ORIGINAL)
	_menu.add_radio_check_item(NotLightL10n.text("audio.menu.use_optimized"), MENU_USE_OPTIMIZED)
	_menu.add_separator()
	_menu.add_item(NotLightL10n.text("runtime.ui.video_board_player.83c2b4778a"), MENU_DELETE_ORIGINAL)
	_menu.add_item(NotLightL10n.text("audio.menu.delete_optimized"), MENU_DELETE_OPTIMIZED)
	_menu.id_pressed.connect(_on_menu_pressed)
	add_child(_menu)


func _process(_delta: float) -> void:
	if _video == null or _video.stream == null:
		return
	# The decoder keeps playing when the card is temporarily outside the viewport,
	# while hidden chrome does no per-frame slider/label work. At far zoom the live
	# VideoStreamPlayer surface remains visible, so motion is still discoverable.
	if not is_visible_in_tree():
		return
	if duration <= 0.0:
		var stream_length: float = _video.get_stream_length()
		if stream_length > 0.0:
			duration = stream_length
			_seek.max_value = duration
	if _controls != null and _controls.visible and not _user_seeking:
		var position_value: float = maxf(0.0, _video.stream_position)
		if _seek.is_visible_in_tree():
			_seek.set_value_no_signal(clampf(position_value, 0.0, maxf(_seek.max_value, 1.0)))
		if _time_label.is_visible_in_tree():
			_time_label.text = NotLightL10n.text("ui.format.media_time_pair") % [_format_time(position_value), _format_time(duration)]


func _update_responsive_controls() -> void:
	if _title_label == null or _header == null or _controls == null:
		return
	var width: float = size.x if expanded else _inline_screen_size.x
	var height: float = size.y if expanded else _inline_screen_size.y
	if expanded:
		_header.visible = true
		_controls.visible = true
		_title_label.visible = true
		_status_label.visible = not _status_label.text.is_empty()
		_time_label.visible = width >= 440.0
		_mute_button.visible = width >= 470.0
		_rewind_button.visible = width >= 520.0
		_forward_button.visible = width >= 520.0
		_loop_button.visible = width >= 610.0
		_volume_slider.visible = width >= 720.0
		_seek.visible = true
		return

	# At a distance the media itself is the useful information. Hiding the chrome
	# completely avoids the old "big buttons over an invisible video" effect and
	# also removes the controls' minimum-size pressure from the projected card.
	if width < 320.0 or height < 170.0:
		_header.visible = false
		_controls.visible = false
		return

	_header.visible = true
	_controls.visible = true
	var compact: bool = width < 420.0 or height < 220.0
	_title_label.visible = not compact
	_status_label.visible = not _status_label.text.is_empty() and width >= 420.0
	_time_label.visible = width >= 360.0
	_mute_button.visible = width >= 390.0
	_rewind_button.visible = width >= 500.0
	_forward_button.visible = width >= 500.0
	_loop_button.visible = width >= 570.0
	_volume_slider.visible = width >= 680.0
	_seek.visible = width >= 350.0


func _apply_metadata(metadata: Dictionary) -> void:
	duration = maxf(0.0, float(metadata.get("duration", 0.0)))
	_seek.max_value = maxf(duration, 1.0)
	var width: int = int(metadata.get("width", 0))
	var height: int = int(metadata.get("height", 0))
	if width > 0 and height > 0:
		_video_aspect_ratio = clampf(float(width) / float(height), 0.20, 5.0)
		if _aspect != null:
			_aspect.ratio = _video_aspect_ratio


func _load_stream(
	path: String,
	autoplay: bool,
	restore_position: float = 0.0,
	restore_paused: bool = false
) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		NotLightL10n.bind_text(_status_label, "runtime.ui.video_board_player.5197e544d2")
		_status_label.visible = true
		return
	if path == _loaded_path and _video.stream != null:
		return
	_video.stop()
	_video.stream = null
	_loaded_path = path
	if not ClassDB.class_exists("FFmpegVideoStream"):
		NotLightL10n.bind_text(_status_label, "runtime.ui.video_board_player.62c77f9c1d")
		_status_label.visible = true
		return
	var instance: Object = ClassDB.instantiate("FFmpegVideoStream")
	var stream_resource: VideoStream = instance as VideoStream
	if stream_resource == null:
		NotLightL10n.bind_text(_status_label, "runtime.ui.video_board_player.11ced8010f")
		_status_label.visible = true
		return
	stream_resource.call("set_file", path)
	_video.stream = stream_resource
	call_deferred("_start_loaded_stream", autoplay, restore_position, restore_paused)


func _start_loaded_stream(autoplay: bool, restore_position: float, restore_paused: bool) -> void:
	if _video.stream == null:
		return
	if autoplay:
		_video.play()
		if restore_position > 0.0:
			var limit: float = duration if duration > 0.0 else restore_position
			_video.stream_position = clampf(restore_position, 0.0, limit)
		_video.paused = restore_paused
	_refresh_play_icon()


func _refresh_play_icon() -> void:
	_play_button.text = "▶" if _video == null or not _video.is_playing() or _video.paused else "Ⅱ"


func _on_finished() -> void:
	_seek.value = 0.0
	_refresh_play_icon()


func _on_seek_started() -> void:
	_user_seeking = true
	_resume_after_seek = _video.stream != null and _video.is_playing() and not _video.paused
	if _resume_after_seek:
		_video.paused = true


func _on_seek_ended(_changed: bool) -> void:
	_user_seeking = false
	if _video.stream != null:
		_video.stream_position = _seek.value
		if _resume_after_seek:
			_video.paused = false
	_resume_after_seek = false
	_refresh_play_icon()


func _on_seek_changed(value: float) -> void:
	if _user_seeking:
		_time_label.text = NotLightL10n.text("ui.format.media_time_pair") % [_format_time(value), _format_time(duration)]


func _seek_relative(delta_seconds: float) -> void:
	if _video == null or _video.stream == null:
		return
	var limit: float = duration if duration > 0.0 else maxf(_video.get_stream_length(), 0.0)
	var target: float = maxf(0.0, _video.stream_position + delta_seconds)
	if limit > 0.0:
		target = minf(target, limit)
	_video.stream_position = target
	_seek.value = target


func _on_volume_changed(value: float) -> void:
	if _video == null:
		return
	_video.volume = clampf(value, 0.0, 1.0)
	if value > 0.001:
		_remembered_volume = value
	_mute_button.text = "×♪" if value <= 0.001 else "♪"


func _on_loop_toggled(enabled: bool) -> void:
	if _video != null:
		_video.loop = enabled


func _toggle_mute() -> void:
	if _video == null:
		return
	if _video.volume > 0.001:
		_remembered_volume = _video.volume
		_video.volume = 0.0
		_volume_slider.set_value_no_signal(0.0)
		_mute_button.text = "×♪"
	else:
		_video.volume = maxf(_remembered_volume, 0.35)
		_volume_slider.set_value_no_signal(_video.volume)
		_mute_button.text = "♪"


func _open_menu() -> void:
	_refresh_variant_menu()
	var rect: Rect2 = _menu_button.get_global_rect()
	_menu.position = Vector2i(int(rect.position.x), int(rect.end.y + 3.0))
	_menu.popup()


func _refresh_variant_menu() -> void:
	if _menu == null or media == null or asset_id.is_empty():
		return
	var has_original: bool = media.has_variant(asset_id, VideoMediaService.VARIANT_ORIGINAL)
	var has_optimized: bool = media.has_variant(asset_id, VideoMediaService.VARIANT_OPTIMIZED)
	var preferred: String = media.preferred_variant(asset_id)
	var original_index: int = _menu.get_item_index(MENU_USE_ORIGINAL)
	var optimized_index: int = _menu.get_item_index(MENU_USE_OPTIMIZED)
	var delete_original_index: int = _menu.get_item_index(MENU_DELETE_ORIGINAL)
	var delete_optimized_index: int = _menu.get_item_index(MENU_DELETE_OPTIMIZED)
	if original_index >= 0:
		_menu.set_item_disabled(original_index, not has_original)
		_menu.set_item_checked(original_index, preferred == VideoMediaService.VARIANT_ORIGINAL)
	if optimized_index >= 0:
		_menu.set_item_disabled(optimized_index, not has_optimized)
		_menu.set_item_checked(optimized_index, preferred == VideoMediaService.VARIANT_OPTIMIZED)
	if delete_original_index >= 0:
		_menu.set_item_disabled(delete_original_index, not (has_original and has_optimized))
	if delete_optimized_index >= 0:
		_menu.set_item_disabled(delete_optimized_index, not (has_original and has_optimized))


func _on_menu_pressed(menu_id: int) -> void:
	if media == null:
		return
	match menu_id:
		MENU_OPTIMIZE_AUTO:
			if not media.enqueue_optimization(asset_id, "auto"):
				message_requested.emit(NotLightL10n.text("runtime.ui.video_board_player.90f5af416f"))
		MENU_USE_ORIGINAL:
			media.set_preferred_variant(asset_id, VideoMediaService.VARIANT_ORIGINAL)
		MENU_USE_OPTIMIZED:
			media.set_preferred_variant(asset_id, VideoMediaService.VARIANT_OPTIMIZED)
		MENU_DELETE_ORIGINAL:
			if not media.delete_original_variant(asset_id):
				message_requested.emit(NotLightL10n.text("runtime.ui.video_board_player.2e385310f4"))
		MENU_DELETE_OPTIMIZED:
			if not media.delete_optimized_variant(asset_id):
				message_requested.emit(NotLightL10n.text("runtime.ui.video_board_player.cace216651"))
	_refresh_variant_menu()


func _on_playback_variant_changed(
	changed_asset_id: String,
	new_path: String,
	_variant: String
) -> void:
	if changed_asset_id != asset_id:
		return
	var position_value: float = _video.stream_position if _video.stream != null else 0.0
	var was_playing: bool = _video.stream != null and _video.is_playing()
	var was_paused: bool = _video.stream != null and _video.paused
	_load_stream(new_path, was_playing, position_value, was_paused)
	_refresh_variant_menu()


func _on_optimization_progress(
	changed_asset_id: String,
	progress: float,
	message: String
) -> void:
	if changed_asset_id != asset_id:
		return
	_status_label.visible = true
	_status_label.text = NotLightL10n.text("ui.format.percent_int") % int(round(progress * 100.0)) if progress < 1.0 else message


func _on_optimization_failed(changed_asset_id: String, message: String) -> void:
	if changed_asset_id == asset_id:
		_status_label.visible = true
		NotLightL10n.bind_text(_status_label, "runtime.ui.video_board_player.d324003c57")
		message_requested.emit(message)


func _format_time(seconds: float) -> String:
	var total: int = maxi(0, int(seconds))
	var hours: int = total / 3600
	var minutes: int = (total % 3600) / 60
	var secs: int = total % 60
	if hours > 0:
		return NotLightL10n.text("ui.format.time_hms") % [hours, minutes, secs]
	return NotLightL10n.text("ui.format.time_ms") % [minutes, secs]
