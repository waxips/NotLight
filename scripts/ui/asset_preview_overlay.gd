# SPDX-License-Identifier: GPL-3.0-or-later
class_name AssetPreviewOverlay
extends Control

signal closed

const PREVIEW_EXTENT: float = 1280.0
const PDF_PRIORITY_CURRENT: int = 100
const PDF_PRIORITY_PREFETCH: int = 20

var library: AssetLibraryService
var image_cache: ImageAssetCache
var video_media: VideoMediaService
var audio_media: AudioMediaService
var pdf_media: PdfMediaService

var asset_id: String = ""
var _kind: int = AssetKinds.OTHER
var _page_index: int = 0
var _page_count: int = 0
var _duration: float = 0.0
var _user_seeking: bool = false
var _resume_after_seek: bool = false

var _title_label: Label
var _status_label: Label
var _image_view: TextureRect
var _pdf_view: TextureRect
var _waveform_view: TextureRect
var _video_aspect: AspectRatioContainer
var _video_player: VideoStreamPlayer
var _audio_player: AudioStreamPlayer
var _transport: HBoxContainer
var _play_button: Button
var _seek: HSlider
var _time_label: Label
var _volume: HSlider
var _pdf_controls: HBoxContainer
var _pdf_page_label: Label
var _pdf_page_input: LineEdit
var _pdf_prev: Button
var _pdf_next: Button
var _previous_focus: Control


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_as_relative = false
	z_index = 1800
	_build_ui()
	set_process(false)


func configure(
	asset_library: AssetLibraryService,
	cache: ImageAssetCache,
	video_service: VideoMediaService,
	audio_service: AudioMediaService,
	pdf_service: PdfMediaService
) -> void:
	library = asset_library
	image_cache = cache
	video_media = video_service
	audio_media = audio_service
	pdf_media = pdf_service
	if image_cache != null:
		if not image_cache.texture_ready.is_connected(_on_image_ready):
			image_cache.texture_ready.connect(_on_image_ready)
		if not image_cache.texture_failed.is_connected(_on_image_failed):
			image_cache.texture_failed.connect(_on_image_failed)
	if pdf_media != null:
		if not pdf_media.page_ready.is_connected(_on_pdf_page_ready):
			pdf_media.page_ready.connect(_on_pdf_page_ready)
		if not pdf_media.document_ready.is_connected(_on_pdf_document_ready):
			pdf_media.document_ready.connect(_on_pdf_document_ready)
		if not pdf_media.page_failed.is_connected(_on_pdf_page_failed):
			pdf_media.page_failed.connect(_on_pdf_page_failed)
		if not pdf_media.preparation_failed.is_connected(_on_pdf_preparation_failed):
			pdf_media.preparation_failed.connect(_on_pdf_preparation_failed)
	if audio_media != null:
		if not audio_media.waveform_ready.is_connected(_on_audio_waveform_ready):
			audio_media.waveform_ready.connect(_on_audio_waveform_ready)
		if not audio_media.playback_ready.is_connected(_on_audio_playback_ready):
			audio_media.playback_ready.connect(_on_audio_playback_ready)
		if not audio_media.metadata_ready.is_connected(_on_audio_metadata_ready):
			audio_media.metadata_ready.connect(_on_audio_metadata_ready)
		if not audio_media.preparation_failed.is_connected(_on_audio_preparation_failed):
			audio_media.preparation_failed.connect(_on_audio_preparation_failed)


func open_asset(new_asset_id: String) -> void:
	if library == null:
		return
	var clean_id: String = new_asset_id.strip_edges()
	var asset: Dictionary = library.get_asset(clean_id)
	if clean_id.is_empty() or asset.is_empty():
		return
	_stop_media()
	asset_id = clean_id
	_kind = int(asset.get("kind", AssetKinds.OTHER))
	_page_index = 0
	_page_count = 0
	_duration = 0.0
	_title_label.text = str(asset.get("display_name", NotLightL10n.text("library.preview.title")))
	NotLightL10n.bind_text(_status_label, "library.preview.loading")
	_reset_views()
	_previous_focus = get_viewport().gui_get_focus_owner()
	visible = true
	move_to_front()
	grab_focus()
	match _kind:
		AssetKinds.IMAGE:
			_open_image()
		AssetKinds.PDF:
			_open_pdf()
		AssetKinds.VIDEO:
			_open_video()
		AssetKinds.AUDIO:
			_open_audio()
		_:
			NotLightL10n.bind_text(_status_label, "library.preview.unsupported")


func close_preview() -> void:
	if not visible:
		return
	_stop_media()
	asset_id = ""
	_kind = AssetKinds.OTHER
	visible = false
	set_process(false)
	if _previous_focus != null and is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	_previous_focus = null
	closed.emit()


func _build_ui() -> void:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.035, 0.045, 0.040, 0.72)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	add_child(backdrop)

	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = "SettingsModalPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.08
	panel.anchor_top = 0.07
	panel.anchor_right = 0.92
	panel.anchor_bottom = 0.93
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0
	panel.custom_minimum_size = Vector2(640.0, 420.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)
	var title_box: VBoxContainer = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 1)
	header.add_child(title_box)
	_title_label = Label.new()
	_title_label.theme_type_variation = "TitleLabel"
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_box.add_child(_title_label)
	_status_label = Label.new()
	_status_label.theme_type_variation = "CaptionLabel"
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_box.add_child(_status_label)
	var close_button: Button = Button.new()
	close_button.icon = load("res://assets/icons/close.svg") as Texture2D
	NotLightL10n.bind_tooltip(close_button, "library.preview.close")
	close_button.theme_type_variation = "IconButton"
	close_button.custom_minimum_size = Vector2(40.0, 40.0)
	close_button.pressed.connect(close_preview)
	header.add_child(close_button)

	var stage_panel: PanelContainer = PanelContainer.new()
	stage_panel.theme_type_variation = "SoftPanel"
	stage_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_panel.custom_minimum_size = Vector2(0.0, 280.0)
	root.add_child(stage_panel)
	var stage: Control = Control.new()
	stage.clip_contents = true
	stage_panel.add_child(stage)

	_image_view = _make_texture_view()
	stage.add_child(_image_view)
	_pdf_view = _make_texture_view()
	stage.add_child(_pdf_view)
	_waveform_view = _make_texture_view()
	_waveform_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stage.add_child(_waveform_view)

	_video_aspect = AspectRatioContainer.new()
	_video_aspect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_video_aspect.ratio = 16.0 / 9.0
	_video_aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	_video_aspect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_video_aspect)
	_video_player = VideoStreamPlayer.new()
	_video_player.expand = true
	_video_player.volume = 0.82
	_video_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video_player.finished.connect(_on_media_finished)
	_video_aspect.add_child(_video_player)
	_video_player.add_to_group(AppAudioService.FOREGROUND_MEDIA_GROUP)

	_audio_player = AudioStreamPlayer.new()
	_audio_player.volume_linear = 0.82
	_audio_player.finished.connect(_on_media_finished)
	add_child(_audio_player)
	_audio_player.add_to_group(AppAudioService.FOREGROUND_MEDIA_GROUP)

	_pdf_controls = HBoxContainer.new()
	_pdf_controls.alignment = BoxContainer.ALIGNMENT_CENTER
	_pdf_controls.add_theme_constant_override("separation", 8)
	root.add_child(_pdf_controls)
	_pdf_prev = Button.new()
	_pdf_prev.text = "←"
	_pdf_prev.theme_type_variation = "GhostButton"
	_pdf_prev.pressed.connect(func() -> void: _show_pdf_page(_page_index - 1))
	_pdf_controls.add_child(_pdf_prev)
	_pdf_page_label = Label.new()
	_pdf_page_label.theme_type_variation = "CaptionStrongLabel"
	_pdf_page_label.custom_minimum_size = Vector2(120.0, 0.0)
	_pdf_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pdf_controls.add_child(_pdf_page_label)
	_pdf_page_input = LineEdit.new()
	_pdf_page_input.max_length = 6
	_pdf_page_input.custom_minimum_size = Vector2(94.0, 36.0)
	_pdf_page_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pdf_page_input.editable = false
	NotLightL10n.bind_placeholder_text(_pdf_page_input, "library.preview.pdf_jump_placeholder")
	NotLightL10n.bind_tooltip(_pdf_page_input, "library.preview.pdf_jump")
	_pdf_page_input.text_submitted.connect(_on_pdf_page_submitted)
	_pdf_page_input.focus_entered.connect(func() -> void: _pdf_page_input.select_all())
	_pdf_controls.add_child(_pdf_page_input)
	_pdf_next = Button.new()
	_pdf_next.text = "→"
	_pdf_next.theme_type_variation = "GhostButton"
	_pdf_next.pressed.connect(func() -> void: _show_pdf_page(_page_index + 1))
	_pdf_controls.add_child(_pdf_next)

	_transport = HBoxContainer.new()
	_transport.add_theme_constant_override("separation", 8)
	root.add_child(_transport)
	_play_button = Button.new()
	_play_button.text = "▶"
	_play_button.theme_type_variation = "PrimaryButton"
	_play_button.custom_minimum_size = Vector2(52.0, 38.0)
	_play_button.pressed.connect(_toggle_play)
	_transport.add_child(_play_button)
	_seek = HSlider.new()
	_seek.scrollable = false
	_seek.min_value = 0.0
	_seek.max_value = 1.0
	_seek.step = 0.01
	_seek.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seek.drag_started.connect(_on_seek_started)
	_seek.drag_ended.connect(_on_seek_ended)
	_seek.value_changed.connect(_on_seek_changed)
	_transport.add_child(_seek)
	_time_label = Label.new()
	_time_label.text = NotLightL10n.text("ui.format.media_time_pair") % [NotLightL10n.text("ui.format.time_zero"), NotLightL10n.text("ui.format.time_zero")]
	_time_label.theme_type_variation = "CaptionStrongLabel"
	_time_label.custom_minimum_size = Vector2(120.0, 0.0)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_transport.add_child(_time_label)
	var volume_label: Label = Label.new()
	volume_label.text = "♪"
	volume_label.theme_type_variation = "CaptionStrongLabel"
	_transport.add_child(volume_label)
	_volume = HSlider.new()
	_volume.scrollable = false
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.01
	_volume.value = 0.82
	_volume.custom_minimum_size = Vector2(110.0, 24.0)
	_volume.value_changed.connect(_on_volume_changed)
	_transport.add_child(_volume)
	_reset_views()


func _make_texture_view() -> TextureRect:
	var view: TextureRect = TextureRect.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return view


func _reset_views() -> void:
	_image_view.visible = false
	_pdf_view.visible = false
	_waveform_view.visible = false
	_video_aspect.visible = false
	_pdf_controls.visible = false
	_transport.visible = false
	_image_view.texture = null
	_pdf_view.texture = null
	_waveform_view.texture = null
	_pdf_page_input.text = ""
	_pdf_page_input.editable = false
	_user_seeking = false
	_resume_after_seek = false
	_seek.set_value_no_signal(0.0)
	_seek.max_value = 1.0
	_seek.editable = false
	_time_label.text = NotLightL10n.text("ui.format.media_time_pair") % [NotLightL10n.text("ui.format.time_zero"), NotLightL10n.text("ui.format.time_zero")]
	_play_button.text = "▶"
	_play_button.disabled = true


func _open_image() -> void:
	_image_view.visible = true
	if image_cache == null:
		NotLightL10n.bind_text(_status_label, "library.preview.backend_unavailable")
		return
	var texture: Texture2D = image_cache.request_texture(asset_id, PREVIEW_EXTENT)
	if texture != null:
		_image_view.texture = texture
		NotLightL10n.bind_text(_status_label, "library.preview.ready")


func _open_pdf() -> void:
	_pdf_view.visible = true
	_pdf_controls.visible = true
	if pdf_media == null:
		NotLightL10n.bind_text(_status_label, "library.preview.backend_unavailable")
		return
	pdf_media.ensure_document(asset_id, PDF_PRIORITY_CURRENT)
	_page_count = maxi(0, pdf_media.get_page_count(asset_id))
	_show_pdf_page(0)


func _show_pdf_page(requested_page: int) -> void:
	if pdf_media == null or asset_id.is_empty() or _kind != AssetKinds.PDF:
		return
	var max_index: int = maxi(0, _page_count - 1)
	_page_index = clampi(requested_page, 0, max_index) if _page_count > 0 else 0
	var texture: Texture2D = pdf_media.request_page(asset_id, _page_index, PREVIEW_EXTENT, PDF_PRIORITY_CURRENT)
	if texture != null:
		_pdf_view.texture = texture
		NotLightL10n.bind_text(_status_label, "library.preview.ready")
	else:
		_pdf_view.texture = null
		NotLightL10n.bind_text(_status_label, "library.preview.loading")
	_refresh_pdf_controls()
	_prefetch_pdf_neighbors()


func _prefetch_pdf_neighbors() -> void:
	if pdf_media == null or asset_id.is_empty() or _kind != AssetKinds.PDF or _page_count <= 1:
		return
	for neighbor: int in [_page_index - 1, _page_index + 1]:
		if neighbor < 0 or neighbor >= _page_count:
			continue
		pdf_media.request_page(asset_id, neighbor, PREVIEW_EXTENT, PDF_PRIORITY_PREFETCH)


func _refresh_pdf_controls() -> void:
	var shown_count: int = maxi(1, _page_count)
	_pdf_page_label.text = NotLightL10n.text("library.preview.pdf_page", {"page": _page_index + 1, "count": shown_count})
	_pdf_page_input.text = str(_page_index + 1) if _page_count > 0 else ""
	_pdf_page_input.editable = _page_count > 0
	_pdf_prev.disabled = _page_index <= 0
	_pdf_next.disabled = _page_count <= 0 or _page_index >= _page_count - 1


func _on_pdf_page_submitted(value: String) -> void:
	var clean: String = value.strip_edges()
	if _page_count <= 0 or not clean.is_valid_int():
		_refresh_pdf_controls()
		return
	var one_based_page: int = clampi(int(clean), 1, _page_count)
	_show_pdf_page(one_based_page - 1)
	_pdf_page_input.select_all()


func _open_video() -> void:
	_video_aspect.visible = true
	_transport.visible = true
	if video_media == null:
		NotLightL10n.bind_text(_status_label, "library.preview.backend_unavailable")
		return
	var path: String = video_media.resolve_playback_path(asset_id)
	if path.is_empty() or not FileAccess.file_exists(path):
		NotLightL10n.bind_text(_status_label, "library.preview.file_unavailable")
		return
	if not ClassDB.class_exists("FFmpegVideoStream"):
		NotLightL10n.bind_text(_status_label, "library.preview.video_backend_unavailable")
		return
	var instance: Object = ClassDB.instantiate("FFmpegVideoStream")
	var stream: VideoStream = instance as VideoStream
	if stream == null:
		NotLightL10n.bind_text(_status_label, "library.preview.video_backend_unavailable")
		return
	stream.call("set_file", path)
	_video_player.stream = stream
	_duration = maxf(0.0, _video_player.get_stream_length())
	if _duration > 0.0:
		_seek.max_value = _duration
		_seek.editable = true
	_update_time(0.0)
	_play_button.disabled = false
	NotLightL10n.bind_text(_status_label, "library.preview.ready")
	_video_player.play()
	_play_button.text = "Ⅱ"
	set_process(true)


func _open_audio() -> void:
	_waveform_view.visible = true
	_transport.visible = true
	if audio_media == null:
		NotLightL10n.bind_text(_status_label, "library.preview.backend_unavailable")
		return
	var waveform: Texture2D = audio_media.get_waveform(asset_id)
	if waveform != null:
		_waveform_view.texture = waveform
	var stream: AudioStream = audio_media.load_stream(asset_id)
	if stream != null:
		_set_audio_stream(stream, true)
	else:
		NotLightL10n.bind_text(_status_label, "library.preview.audio_preparing")
		set_process(false)


func _set_audio_stream(stream: AudioStream, autoplay: bool = false) -> void:
	_audio_player.stop()
	_audio_player.stream = stream
	_duration = maxf(0.0, stream.get_length())
	_seek.max_value = maxf(1.0, _duration)
	_seek.editable = _duration > 0.0
	_play_button.disabled = false
	NotLightL10n.bind_text(_status_label, "library.preview.ready")
	_update_time(0.0)
	if autoplay:
		_audio_player.play()
		_play_button.text = "Ⅱ"
	set_process(_audio_player.has_stream_playback() and not _audio_player.stream_paused)


func _process(_delta: float) -> void:
	if not visible:
		return
	if _kind == AssetKinds.VIDEO and _video_player.stream != null:
		if _duration <= 0.0:
			var length: float = _video_player.get_stream_length()
			if length > 0.0:
				_duration = length
				_seek.max_value = length
				_seek.editable = true
		var texture: Texture2D = _video_player.get_video_texture()
		if texture != null:
			var frame_size: Vector2 = texture.get_size()
			if frame_size.y > 0.0:
				_video_aspect.ratio = frame_size.x / frame_size.y
		if not _user_seeking:
			var position: float = maxf(0.0, _video_player.stream_position)
			_seek.set_value_no_signal(clampf(position, 0.0, maxf(1.0, _seek.max_value)))
			_update_time(position)
	elif _kind == AssetKinds.AUDIO and _audio_player.stream != null and not _user_seeking:
		var audio_position: float = _audio_player.get_playback_position() if _audio_player.has_stream_playback() else _seek.value
		_seek.set_value_no_signal(clampf(audio_position, 0.0, maxf(1.0, _seek.max_value)))
		_update_time(audio_position)


func _toggle_play() -> void:
	if _kind == AssetKinds.VIDEO:
		if _video_player.stream == null:
			return
		if _video_player.paused:
			_video_player.paused = false
		elif _video_player.is_playing():
			_video_player.paused = true
		else:
			_video_player.play()
		_play_button.text = "▶" if _video_player.paused else "Ⅱ"
		set_process(not _video_player.paused)
	elif _kind == AssetKinds.AUDIO:
		if _audio_player.stream == null:
			var stream: AudioStream = audio_media.load_stream(asset_id) if audio_media != null else null
			if stream == null:
				return
			_set_audio_stream(stream)
			_audio_player.play(_seek.value)
			_play_button.text = "Ⅱ"
			set_process(true)
			return
		if _audio_player.stream_paused:
			_audio_player.stream_paused = false
		elif _audio_player.has_stream_playback():
			_audio_player.stream_paused = true
		else:
			_audio_player.play(_seek.value)
		_play_button.text = "▶" if _audio_player.stream_paused else "Ⅱ"
		set_process(not _audio_player.stream_paused)


func _on_seek_started() -> void:
	_user_seeking = true
	if _kind == AssetKinds.VIDEO:
		_resume_after_seek = _video_player.stream != null and _video_player.is_playing() and not _video_player.paused
		if _resume_after_seek:
			_video_player.paused = true
	elif _kind == AssetKinds.AUDIO:
		_resume_after_seek = _audio_player.has_stream_playback() and not _audio_player.stream_paused
		if _audio_player.has_stream_playback():
			_audio_player.stream_paused = true


func _on_seek_ended(_changed: bool) -> void:
	var target: float = clampf(_seek.value, 0.0, maxf(0.0, _duration))
	_user_seeking = false
	if _kind == AssetKinds.VIDEO and _video_player.stream != null:
		_video_player.stream_position = target
		if _resume_after_seek:
			_video_player.paused = false
	elif _kind == AssetKinds.AUDIO and _audio_player.stream != null:
		if _audio_player.has_stream_playback():
			_audio_player.seek(target)
			_audio_player.stream_paused = not _resume_after_seek
		elif _resume_after_seek:
			_audio_player.play(target)
	if _resume_after_seek:
		set_process(true)
	_resume_after_seek = false
	_update_time(target)


func _on_seek_changed(value: float) -> void:
	if _user_seeking:
		_update_time(value)


func _on_volume_changed(value: float) -> void:
	_video_player.volume = value
	_audio_player.volume_linear = value


func _on_image_ready(ready_asset_id: String) -> void:
	if visible and _kind == AssetKinds.IMAGE and ready_asset_id == asset_id:
		_open_image()


func _on_image_failed(ready_asset_id: String, message: String) -> void:
	if visible and _kind == AssetKinds.IMAGE and ready_asset_id == asset_id:
		_status_label.text = message


func _on_pdf_page_ready(ready_asset_id: String, ready_page_index: int) -> void:
	if visible and _kind == AssetKinds.PDF and ready_asset_id == asset_id and ready_page_index == _page_index:
		var texture: Texture2D = pdf_media.request_page(asset_id, _page_index, PREVIEW_EXTENT, PDF_PRIORITY_CURRENT)
		if texture != null:
			_pdf_view.texture = texture
			NotLightL10n.bind_text(_status_label, "library.preview.ready")


func _on_pdf_document_ready(ready_asset_id: String, _metadata: Dictionary) -> void:
	if visible and _kind == AssetKinds.PDF and ready_asset_id == asset_id:
		_page_count = maxi(0, pdf_media.get_page_count(asset_id))
		_refresh_pdf_controls()
		_show_pdf_page(_page_index)


func _on_pdf_page_failed(ready_asset_id: String, ready_page_index: int, message: String) -> void:
	if visible and _kind == AssetKinds.PDF and ready_asset_id == asset_id and ready_page_index == _page_index:
		_status_label.text = message


func _on_pdf_preparation_failed(ready_asset_id: String, message: String) -> void:
	if visible and _kind == AssetKinds.PDF and ready_asset_id == asset_id:
		_status_label.text = message


func _on_audio_waveform_ready(ready_asset_id: String) -> void:
	if visible and _kind == AssetKinds.AUDIO and ready_asset_id == asset_id and audio_media != null:
		_waveform_view.texture = audio_media.get_waveform(asset_id, false)


func _on_audio_playback_ready(ready_asset_id: String, _path: String) -> void:
	if not visible or _kind != AssetKinds.AUDIO or ready_asset_id != asset_id or audio_media == null:
		return
	var stream: AudioStream = audio_media.load_stream(asset_id)
	if stream != null:
		_set_audio_stream(stream, true)


func _on_audio_metadata_ready(ready_asset_id: String, metadata: Dictionary) -> void:
	if visible and _kind == AssetKinds.AUDIO and ready_asset_id == asset_id:
		var metadata_duration: float = maxf(0.0, float(metadata.get("duration", 0.0)))
		if metadata_duration > 0.0:
			_duration = metadata_duration
			_seek.max_value = metadata_duration
			_seek.editable = true
			_update_time(_seek.value)


func _on_audio_preparation_failed(ready_asset_id: String, message: String) -> void:
	if visible and _kind == AssetKinds.AUDIO and ready_asset_id == asset_id:
		_status_label.text = message


func _on_media_finished() -> void:
	_play_button.text = "▶"
	if _seek != null:
		_seek.set_value_no_signal(0.0)
	_update_time(0.0)
	set_process(false)


func _stop_media() -> void:
	if _video_player != null:
		_video_player.stop()
		_video_player.paused = false
		_video_player.stream = null
	if _audio_player != null:
		_audio_player.stop()
		_audio_player.stream_paused = false
		_audio_player.stream = null
	set_process(false)


func _update_time(position: float) -> void:
	_time_label.text = NotLightL10n.text("ui.format.media_time_pair") % [_format_time(position), _format_time(_duration)]


func _format_time(seconds: float) -> String:
	var total: int = maxi(0, int(seconds))
	var hours: int = total / 3600
	var minutes: int = (total % 3600) / 60
	var secs: int = total % 60
	return NotLightL10n.text("ui.format.time_hms") % [hours, minutes, secs] if hours > 0 else NotLightL10n.text("ui.format.time_ms") % [minutes, secs]


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or event is not InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_ESCAPE:
		close_preview()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_SPACE and (_kind == AssetKinds.VIDEO or _kind == AssetKinds.AUDIO):
		_toggle_play()
		get_viewport().set_input_as_handled()


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			close_preview()
