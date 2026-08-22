# SPDX-License-Identifier: GPL-3.0-or-later
class_name NoteResourceEmbedBlock
extends PanelContainer

signal preview_requested(asset_id: String)
signal live_activation_requested(block: NoteResourceEmbedBlock)

const IMAGE_MIN_HEIGHT: float = 180.0
const IMAGE_MAX_HEIGHT: float = 420.0
const IMAGE_REQUEST_EXTENT: float = 1280.0
const VIDEO_MIN_HEIGHT: float = 220.0
const VIDEO_MAX_HEIGHT: float = 680.0
const VIDEO_DEFAULT_ASPECT: float = 16.0 / 9.0
const AUDIO_WAVEFORM_HEIGHT: float = 84.0
const PDF_PREVIEW_HEIGHT: float = 620.0
const PDF_REQUEST_EXTENT: float = 1280.0
const PDF_MAX_REQUEST_EXTENT: float = 3072.0
const PDF_ZOOM_MIN: float = 0.5
const PDF_ZOOM_MAX: float = 4.0
const PDF_ZOOM_STEP: float = 0.25
const PDF_PAGE_MARGIN: float = 28.0
const PROCESS_INTERVAL_SECONDS: float = 0.12

var _library: AssetLibraryService
var _image_cache: ImageAssetCache
var _video_media: VideoMediaService
var _audio_media: AudioMediaService
var _pdf_media: PdfMediaService
var _hash_sha256: String = ""
var _caption: String = ""
var _asset_id: String = ""
var _kind: int = AssetKinds.OTHER
var _rich_preview_enabled: bool = true
var _root: VBoxContainer
var _title_label: Label
var _meta_label: Label
var _content: VBoxContainer
var _open_button: Button
var _show_inline_button: Button
var _image: TextureRect
var _video_frame: PanelContainer
var _video_aspect: AspectRatioContainer
var _video_player: VideoStreamPlayer
var _video_poster: TextureRect
var _video_placeholder: Label
var _video_play_button: Button
var _video_seek: HSlider
var _video_seek_dragging: bool = false
var _video_time: Label
var _video_aspect_ratio: float = VIDEO_DEFAULT_ASPECT
var _video_live_aspect_resolved: bool = false
var _audio_player: AudioStreamPlayer
var _audio_waveform: TextureRect
var _audio_play_button: Button
var _audio_seek: HSlider
var _audio_time: Label
var _pdf_scroll: ScrollContainer
var _pdf_canvas: Control
var _pdf_view: TextureRect
var _pdf_prev: Button
var _pdf_next: Button
var _pdf_page_label: Label
var _pdf_zoom_label: Label
var _pdf_zoom: float = PDF_ZOOM_MIN
var _pdf_page_index: int = 0
var _pdf_page_count: int = 0
var _live_materialized: bool = false
var _saved_position: float = 0.0
var _process_accumulator: float = 0.0


func _ready() -> void:
	theme_type_variation = "NoteResourceEmbedPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_process(false)
	_build_ui()
	_refresh()


func _exit_tree() -> void:
	_disconnect_services()
	deactivate_live()


func configure(
	library: AssetLibraryService,
	image_cache: ImageAssetCache,
	video_media: VideoMediaService,
	audio_media: AudioMediaService,
	pdf_media: PdfMediaService,
	hash_sha256: String,
	caption: String = "",
	rich_preview_enabled: bool = true
) -> void:
	_disconnect_services()
	deactivate_live()
	_library = library
	_image_cache = image_cache
	_video_media = video_media
	_audio_media = audio_media
	_pdf_media = pdf_media
	_hash_sha256 = hash_sha256.strip_edges().to_lower()
	_caption = caption.strip_edges()
	_rich_preview_enabled = rich_preview_enabled
	_connect_services()
	if _root != null:
		_refresh()


func get_asset_id() -> String:
	return _asset_id


func is_live() -> bool:
	return _live_materialized


func activate_live() -> bool:
	if _asset_id.is_empty():
		return false
	if _kind == AssetKinds.VIDEO:
		if not _ensure_video_stream():
			return false
		_live_materialized = true
		_video_live_aspect_resolved = false
		_video_poster.visible = false
		_video_player.visible = true
		_video_player.play()
		if _saved_position > 0.0:
			_video_player.stream_position = _saved_position
		_video_play_button.text = "Ⅱ"
		set_process(true)
		return true
	if _kind == AssetKinds.AUDIO:
		if not _ensure_audio_stream():
			return false
		_live_materialized = true
		_audio_player.play(_saved_position)
		_audio_play_button.text = "Ⅱ"
		set_process(true)
		return true
	return false


func deactivate_live() -> void:
	if _video_player != null and _video_player.stream != null:
		if _video_player.is_playing():
			_saved_position = maxf(0.0, _video_player.stream_position)
		_video_player.stop()
		_video_player.stream = null
		_video_player.visible = false
		if _video_poster != null:
			_video_poster.visible = true
		if _video_play_button != null:
			_video_play_button.text = "▶"
	if _audio_player != null and _audio_player.stream != null:
		if _audio_player.has_stream_playback():
			_saved_position = maxf(0.0, _audio_player.get_playback_position())
		_audio_player.stop()
		_audio_player.stream = null
		if _audio_play_button != null:
			_audio_play_button.text = "▶"
	_live_materialized = false
	set_process(false)


func _process(delta: float) -> void:
	_process_accumulator += delta
	if _process_accumulator < PROCESS_INTERVAL_SECONDS:
		return
	_process_accumulator = 0.0
	if _kind == AssetKinds.VIDEO and _video_player != null and _video_player.stream != null:
		if not _video_live_aspect_resolved:
			var live_texture: Texture2D = _video_player.get_video_texture()
			if live_texture != null and live_texture.get_width() > 1 and live_texture.get_height() > 1:
				_update_video_aspect_from_texture(live_texture)
				_video_live_aspect_resolved = true
		var duration: float = maxf(0.0, _video_player.get_stream_length())
		var position: float = maxf(0.0, _video_player.stream_position)
		if duration > 0.0 and not _video_seek_dragging:
			_video_seek.max_value = duration
			_video_seek.value = minf(position, duration)
		_video_time.text = _time_text(position, duration)
	if _kind == AssetKinds.AUDIO and _audio_player != null and _audio_player.stream != null:
		var audio_duration: float = maxf(0.0, _audio_player.stream.get_length())
		var audio_position: float = maxf(0.0, _audio_player.get_playback_position())
		if not _audio_seek.has_focus() and audio_duration > 0.0:
			_audio_seek.max_value = audio_duration
			_audio_seek.value = minf(audio_position, audio_duration)
		_audio_time.text = _time_text(audio_position, audio_duration)


func _build_ui() -> void:
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 8)
	add_child(_root)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	_root.add_child(header)
	_title_label = Label.new()
	_title_label.theme_type_variation = "BodyStrongLabel"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_title_label)
	_open_button = Button.new()
	_open_button.icon = load("res://assets/icons/library.svg") as Texture2D
	_open_button.theme_type_variation = "CompactIconButton"
	_open_button.custom_minimum_size = Vector2(32.0, 32.0)
	_open_button.focus_mode = Control.FOCUS_NONE
	NotLightL10n.bind_tooltip(_open_button, "notes.embed.open")
	_open_button.pressed.connect(_request_preview)
	header.add_child(_open_button)
	_meta_label = Label.new()
	_meta_label.theme_type_variation = "CaptionLabel"
	_meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_meta_label)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 7)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_child(_content)
	_show_inline_button = Button.new()
	NotLightL10n.bind_text(_show_inline_button, "notes.embed.show_inline")
	_show_inline_button.theme_type_variation = "GhostButton"
	_show_inline_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_show_inline_button.pressed.connect(_on_show_inline_pressed)
	_root.add_child(_show_inline_button)


func _refresh() -> void:
	if _root == null:
		return
	_clear_content()
	_asset_id = ""
	_kind = AssetKinds.OTHER
	_open_button.disabled = true
	_show_inline_button.visible = false
	if _library == null or not NoteResourceEmbed.is_sha256(_hash_sha256):
		NotLightL10n.bind_text(_title_label, "notes.embed.invalid")
		_meta_label.text = _hash_summary()
		return
	var asset: Dictionary = _library.find_asset_by_hash(_hash_sha256)
	if asset.is_empty():
		_title_label.text = _caption if not _caption.is_empty() else NotLightL10n.text("notes.embed.missing")
		_meta_label.text = NotLightL10n.text("notes.embed.missing_hash", {"hash": _hash_summary()})
		return
	_asset_id = str(asset.get("id", "")).strip_edges()
	_kind = int(asset.get("kind", AssetKinds.OTHER))
	if not NoteResourceEmbed.is_embeddable_kind(_kind):
		_title_label.text = _caption if not _caption.is_empty() else str(asset.get("display_name", _asset_id))
		_meta_label.text = NotLightL10n.text("notes.embed.unsupported_kind", {"kind": AssetKinds.label(_kind)})
		return
	var display_name: String = _caption if not _caption.is_empty() else str(asset.get("display_name", _asset_id))
	_title_label.text = display_name
	_meta_label.text = NotLightL10n.text("ui.format.hash_metadata") % [
		AssetKinds.label(_kind),
		_format_bytes(int(asset.get("byte_size", 0))),
		_hash_summary(),
	]
	_open_button.disabled = false
	if _rich_preview_enabled:
		_build_rich_content()
	else:
		_show_inline_button.visible = true
		_meta_label.text += NotLightL10n.text("ui.format.append_middle_dot") % NotLightL10n.text("notes.embed.preview_disabled")


func _build_rich_content() -> void:
	match _kind:
		AssetKinds.IMAGE:
			_build_image_preview()
		AssetKinds.VIDEO:
			_build_video_preview()
		AssetKinds.AUDIO:
			_build_audio_preview()
		AssetKinds.PDF:
			_build_pdf_preview()


func _build_image_preview() -> void:
	_image = TextureRect.new()
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.custom_minimum_size = Vector2(0.0, IMAGE_MIN_HEIGHT)
	_image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_image.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_image.gui_input.connect(_on_image_input)
	_content.add_child(_image)
	_refresh_image_texture()


func _build_video_preview() -> void:
	_video_aspect_ratio = VIDEO_DEFAULT_ASPECT
	_video_live_aspect_resolved = false
	_video_frame = PanelContainer.new()
	_video_frame.theme_type_variation = "NoteEmbeddedMediaFrame"
	_video_frame.custom_minimum_size = Vector2(0.0, VIDEO_MIN_HEIGHT)
	_video_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_video_frame.clip_contents = true
	_video_frame.resized.connect(_update_video_geometry)
	_content.add_child(_video_frame)
	_video_aspect = AspectRatioContainer.new()
	_video_aspect.ratio = VIDEO_DEFAULT_ASPECT
	_video_aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	_video_aspect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_video_frame.add_child(_video_aspect)
	var stack: Control = Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_PASS
	_video_aspect.add_child(stack)
	_video_poster = TextureRect.new()
	_video_poster.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_video_poster.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_video_poster.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stack.add_child(_video_poster)
	_video_placeholder = Label.new()
	_video_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_video_placeholder.text = NotLightL10n.text("ui.format.video_placeholder") % AssetKinds.label(AssetKinds.VIDEO)
	_video_placeholder.theme_type_variation = "BodyMutedLabel"
	_video_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_video_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_video_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_video_placeholder)
	_video_player = VideoStreamPlayer.new()
	_video_player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_video_player.expand = true
	_video_player.visible = false
	stack.add_child(_video_player)
	_video_player.add_to_group(AppAudioService.FOREGROUND_MEDIA_GROUP)
	var transport: HBoxContainer = HBoxContainer.new()
	transport.add_theme_constant_override("separation", 8)
	_content.add_child(transport)
	_video_play_button = Button.new()
	_video_play_button.text = "▶"
	NotLightL10n.bind_tooltip(_video_play_button, "notes.embed.play")
	_video_play_button.theme_type_variation = "CompactIconButton"
	_video_play_button.custom_minimum_size = Vector2(36.0, 34.0)
	_video_play_button.pressed.connect(_on_video_play_pressed)
	transport.add_child(_video_play_button)
	_video_seek = HSlider.new()
	_video_seek.scrollable = false
	_video_seek.min_value = 0.0
	_video_seek.max_value = 1.0
	_video_seek.step = 0.05
	_video_seek.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_video_seek.custom_minimum_size = Vector2(80.0, 24.0)
	_video_seek.drag_started.connect(_on_video_seek_drag_started)
	_video_seek.drag_ended.connect(_on_video_seek_drag_ended)
	transport.add_child(_video_seek)
	_video_time = Label.new()
	_video_time.theme_type_variation = "CaptionLabel"
	_video_time.text = NotLightL10n.text("ui.format.time_zero_short")
	transport.add_child(_video_time)
	if _video_media != null:
		# Never launch FFmpeg thumbnail extraction from a Notes UI rebuild. If the
		# shared service already owns a derived thumbnail, loading it is cheap; if
		# not, the embed remains a neutral media frame until another bounded media
		# workflow prepares it or playback begins explicitly.
		var thumbnail_path: String = _video_media.thumbnail_path(_asset_id)
		if FileAccess.file_exists(thumbnail_path):
			var poster: Texture2D = _video_media.get_thumbnail(_asset_id)
			if poster != null:
				_video_poster.texture = poster
				_video_placeholder.visible = false
				_update_video_aspect_from_texture(poster)
	call_deferred("_update_video_geometry")


func _build_audio_preview() -> void:
	_audio_waveform = TextureRect.new()
	_audio_waveform.custom_minimum_size = Vector2(0.0, AUDIO_WAVEFORM_HEIGHT)
	_audio_waveform.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_audio_waveform.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_audio_waveform.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Waveform textures are neutral alpha masks. Tint at presentation time so the
	# embed follows the NotLight accent without creating another derived cache.
	_audio_waveform.modulate = NotLightTheme.semantic_color("accent")
	_content.add_child(_audio_waveform)
	if _audio_media != null:
		var waveform: Texture2D = _audio_media.get_waveform(_asset_id)
		if waveform != null:
			_audio_waveform.texture = waveform
	var transport: HBoxContainer = HBoxContainer.new()
	transport.add_theme_constant_override("separation", 8)
	_content.add_child(transport)
	_audio_play_button = Button.new()
	_audio_play_button.text = "▶"
	NotLightL10n.bind_tooltip(_audio_play_button, "notes.embed.play")
	_audio_play_button.theme_type_variation = "CompactIconButton"
	_audio_play_button.custom_minimum_size = Vector2(36.0, 34.0)
	_audio_play_button.pressed.connect(_on_audio_play_pressed)
	transport.add_child(_audio_play_button)
	_audio_seek = HSlider.new()
	_audio_seek.scrollable = false
	_audio_seek.min_value = 0.0
	_audio_seek.max_value = 1.0
	_audio_seek.step = 0.05
	_audio_seek.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_audio_seek.drag_ended.connect(_on_audio_seek_drag_ended)
	transport.add_child(_audio_seek)
	_audio_time = Label.new()
	_audio_time.theme_type_variation = "CaptionLabel"
	_audio_time.text = NotLightL10n.text("ui.format.time_zero_short")
	transport.add_child(_audio_time)
	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)
	_audio_player.add_to_group(AppAudioService.FOREGROUND_MEDIA_GROUP)


func _build_pdf_preview() -> void:
	_pdf_zoom = PDF_ZOOM_MIN
	var frame: PanelContainer = PanelContainer.new()
	frame.theme_type_variation = "NoteEmbeddedMediaFrame"
	frame.clip_contents = true
	_content.add_child(frame)
	_pdf_scroll = ScrollContainer.new()
	_pdf_scroll.custom_minimum_size = Vector2(0.0, PDF_PREVIEW_HEIGHT)
	_pdf_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pdf_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_pdf_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_pdf_scroll.resized.connect(_update_pdf_geometry)
	frame.add_child(_pdf_scroll)
	_pdf_canvas = Control.new()
	_pdf_canvas.custom_minimum_size = Vector2(320.0, PDF_PREVIEW_HEIGHT)
	_pdf_scroll.add_child(_pdf_canvas)
	_pdf_view = TextureRect.new()
	_pdf_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pdf_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pdf_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pdf_canvas.add_child(_pdf_view)
	var controls: HBoxContainer = HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	_content.add_child(controls)
	_pdf_prev = Button.new()
	_pdf_prev.text = "‹"
	_pdf_prev.theme_type_variation = "CompactIconButton"
	_pdf_prev.custom_minimum_size = Vector2(34.0, 32.0)
	_pdf_prev.pressed.connect(_on_pdf_previous)
	controls.add_child(_pdf_prev)
	_pdf_page_label = Label.new()
	_pdf_page_label.theme_type_variation = "CaptionLabel"
	_pdf_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pdf_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.add_child(_pdf_page_label)
	_pdf_next = Button.new()
	_pdf_next.text = "›"
	_pdf_next.theme_type_variation = "CompactIconButton"
	_pdf_next.custom_minimum_size = Vector2(34.0, 32.0)
	_pdf_next.pressed.connect(_on_pdf_next)
	controls.add_child(_pdf_next)
	var zoom_out: Button = Button.new()
	zoom_out.text = "−"
	NotLightL10n.bind_tooltip(zoom_out, "notes.embed.pdf_zoom_out")
	zoom_out.theme_type_variation = "CompactIconButton"
	zoom_out.custom_minimum_size = Vector2(34.0, 32.0)
	zoom_out.pressed.connect(_on_pdf_zoom_out)
	controls.add_child(zoom_out)
	_pdf_zoom_label = Label.new()
	_pdf_zoom_label.theme_type_variation = "CaptionLabel"
	_pdf_zoom_label.custom_minimum_size = Vector2(52.0, 0.0)
	_pdf_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.add_child(_pdf_zoom_label)
	var zoom_reset: Button = Button.new()
	zoom_reset.text = "100%"
	NotLightL10n.bind_tooltip(zoom_reset, "notes.embed.pdf_reset_tooltip")
	zoom_reset.theme_type_variation = "GhostButton"
	zoom_reset.custom_minimum_size = Vector2(58.0, 32.0)
	zoom_reset.pressed.connect(_on_pdf_zoom_reset)
	controls.add_child(zoom_reset)
	var zoom_in: Button = Button.new()
	zoom_in.text = "+"
	NotLightL10n.bind_tooltip(zoom_in, "notes.embed.pdf_zoom_in")
	zoom_in.theme_type_variation = "CompactIconButton"
	zoom_in.custom_minimum_size = Vector2(34.0, 32.0)
	zoom_in.pressed.connect(_on_pdf_zoom_in)
	controls.add_child(zoom_in)
	_pdf_page_index = 0
	_pdf_page_count = 0
	if _pdf_media != null:
		_pdf_media.ensure_document(_asset_id, 10)
		_pdf_page_count = maxi(0, _pdf_media.get_page_count(_asset_id))
		_update_pdf_geometry()
		_request_pdf_page()
	_refresh_pdf_controls()


func _clear_content() -> void:
	deactivate_live()
	if _audio_player != null and is_instance_valid(_audio_player):
		_audio_player.queue_free()
	if _content != null:
		for child: Node in _content.get_children():
			_content.remove_child(child)
			child.queue_free()
	_image = null
	_video_frame = null
	_video_aspect = null
	_video_player = null
	_video_poster = null
	_video_placeholder = null
	_video_play_button = null
	_video_seek = null
	_video_seek_dragging = false
	_video_time = null
	_video_aspect_ratio = VIDEO_DEFAULT_ASPECT
	_video_live_aspect_resolved = false
	_audio_player = null
	_audio_waveform = null
	_audio_play_button = null
	_audio_seek = null
	_audio_time = null
	_pdf_scroll = null
	_pdf_canvas = null
	_pdf_view = null
	_pdf_prev = null
	_pdf_next = null
	_pdf_page_label = null
	_pdf_zoom_label = null
	_pdf_zoom = PDF_ZOOM_MIN


func _refresh_image_texture() -> void:
	if _image_cache == null or _asset_id.is_empty() or _image == null:
		return
	var texture: Texture2D = _image_cache.request_texture(_asset_id, IMAGE_REQUEST_EXTENT)
	if texture != null:
		_image.texture = texture
		var intrinsic: Vector2i = _image_cache.get_intrinsic_size(_asset_id)
		if intrinsic.x > 0 and intrinsic.y > 0:
			var aspect: float = float(intrinsic.y) / float(intrinsic.x)
			_image.custom_minimum_size.y = clampf(680.0 * aspect, IMAGE_MIN_HEIGHT, IMAGE_MAX_HEIGHT)



func _update_video_aspect_from_texture(texture: Texture2D) -> void:
	if texture == null:
		return
	var texture_size: Vector2 = texture.get_size()
	if texture_size.x <= 1.0 or texture_size.y <= 1.0:
		return
	_video_aspect_ratio = clampf(texture_size.x / texture_size.y, 0.25, 4.0)
	_update_video_geometry()


func _update_video_geometry() -> void:
	if _video_frame == null or _video_aspect == null:
		return
	_video_aspect.ratio = _video_aspect_ratio
	var available_width: float = maxf(320.0, _video_frame.size.x)
	var target_height: float = clampf(available_width / maxf(0.25, _video_aspect_ratio), VIDEO_MIN_HEIGHT, VIDEO_MAX_HEIGHT)
	_video_frame.custom_minimum_size = Vector2(0.0, target_height)

func _ensure_video_stream() -> bool:
	if _video_media == null or _video_player == null:
		return false
	if _video_player.stream != null:
		return true
	var path: String = _video_media.resolve_playback_path(_asset_id)
	if path.is_empty() or not FileAccess.file_exists(path):
		NotLightL10n.bind_text(_meta_label, "notes.embed.media_unavailable")
		return false
	if not ClassDB.class_exists("FFmpegVideoStream"):
		NotLightL10n.bind_text(_meta_label, "library.preview.video_backend_unavailable")
		return false
	var instance: Object = ClassDB.instantiate("FFmpegVideoStream")
	var stream: VideoStream = instance as VideoStream
	if stream == null:
		NotLightL10n.bind_text(_meta_label, "library.preview.video_backend_unavailable")
		return false
	stream.call("set_file", path)
	_video_player.stream = stream
	return true


func _ensure_audio_stream() -> bool:
	if _audio_media == null or _audio_player == null:
		return false
	if _audio_player.stream != null:
		return true
	var stream: AudioStream = _audio_media.load_stream(_asset_id)
	if stream == null:
		_audio_media.request_prepare(_asset_id, true, true)
		NotLightL10n.bind_text(_meta_label, "library.preview.audio_preparing")
		return false
	_audio_player.stream = stream
	var duration: float = maxf(0.0, stream.get_length())
	_audio_seek.max_value = maxf(1.0, duration)
	return true


func _on_video_play_pressed() -> void:
	if _video_player != null and _video_player.stream != null and _video_player.is_playing():
		_video_player.paused = not _video_player.paused
		_video_play_button.text = "▶" if _video_player.paused else "Ⅱ"
		set_process(not _video_player.paused or (_audio_player != null and _audio_player.has_stream_playback()))
		return
	live_activation_requested.emit(self)


func _on_video_seek_drag_started() -> void:
	_video_seek_dragging = true


func _on_video_seek_drag_ended(value_changed: bool) -> void:
	_video_seek_dragging = false
	if not value_changed or _video_player == null or _video_player.stream == null:
		return
	_saved_position = maxf(0.0, _video_seek.value)
	_video_player.stream_position = _saved_position


func _on_audio_play_pressed() -> void:
	if _audio_player != null and _audio_player.stream != null and _audio_player.has_stream_playback():
		_audio_player.stream_paused = not _audio_player.stream_paused
		_audio_play_button.text = "▶" if _audio_player.stream_paused else "Ⅱ"
		set_process(not _audio_player.stream_paused or (_video_player != null and _video_player.is_playing()))
		return
	live_activation_requested.emit(self)


func _on_audio_seek_drag_ended(value_changed: bool) -> void:
	if not value_changed or _audio_player == null or _audio_player.stream == null:
		return
	_saved_position = maxf(0.0, _audio_seek.value)
	if _audio_player.has_stream_playback():
		_audio_player.seek(_saved_position)


func _on_show_inline_pressed() -> void:
	_rich_preview_enabled = true
	_show_inline_button.visible = false
	_build_rich_content()


func _on_pdf_previous() -> void:
	if _pdf_page_index <= 0:
		return
	_pdf_page_index -= 1
	_request_pdf_page()


func _on_pdf_next() -> void:
	if _pdf_page_count <= 0 or _pdf_page_index >= _pdf_page_count - 1:
		return
	_pdf_page_index += 1
	_request_pdf_page()


func _request_pdf_page() -> void:
	if _pdf_media == null or _pdf_view == null or _asset_id.is_empty():
		return
	var desired_extent: float = minf(PDF_MAX_REQUEST_EXTENT, PDF_REQUEST_EXTENT * _pdf_zoom)
	var texture: Texture2D = _pdf_media.request_page(_asset_id, _pdf_page_index, desired_extent, 10)
	if texture != null:
		_pdf_view.texture = texture
	_refresh_pdf_controls()


func _refresh_pdf_controls() -> void:
	if _pdf_page_label == null:
		return
	var shown_count: int = maxi(1, _pdf_page_count)
	_pdf_page_label.text = NotLightL10n.text("notes.embed.page", {"page": _pdf_page_index + 1, "count": shown_count})
	_pdf_prev.disabled = _pdf_page_index <= 0
	_pdf_next.disabled = _pdf_page_count <= 0 or _pdf_page_index >= _pdf_page_count - 1
	if _pdf_zoom_label != null:
		_pdf_zoom_label.text = NotLightL10n.text("ui.format.percent_int") % int(round(_pdf_zoom * 100.0))


func _update_pdf_geometry() -> void:
	if _pdf_scroll == null or _pdf_canvas == null or _pdf_view == null:
		return
	var page_size: Vector2i = Vector2i(595, 842)
	if _pdf_media != null and not _asset_id.is_empty():
		page_size = _pdf_media.get_page_size(_asset_id)
	if page_size.x <= 0 or page_size.y <= 0:
		page_size = Vector2i(595, 842)
	# 100% means the PDF's logical page size, not "fill the Notes column". The
	# page stays centered at its natural size and only explicit zoom changes its
	# scale. The canvas grows beyond the viewport when needed so ScrollContainer
	# owns panning without stretching the page.
	var scaled_width: float = maxf(1.0, float(page_size.x) * _pdf_zoom)
	var scaled_height: float = maxf(1.0, float(page_size.y) * _pdf_zoom)
	var viewport_width: float = maxf(320.0, _pdf_scroll.size.x)
	var viewport_height: float = maxf(PDF_PREVIEW_HEIGHT, _pdf_scroll.size.y)
	var canvas_width: float = maxf(viewport_width, scaled_width + PDF_PAGE_MARGIN * 2.0)
	var canvas_height: float = maxf(viewport_height, scaled_height + PDF_PAGE_MARGIN * 2.0)
	_pdf_canvas.custom_minimum_size = Vector2(ceil(canvas_width), ceil(canvas_height))
	_pdf_view.size = Vector2(scaled_width, scaled_height)
	_pdf_view.position = Vector2(
		floor((canvas_width - scaled_width) * 0.5),
		floor((canvas_height - scaled_height) * 0.5)
	)


func _set_pdf_zoom(next_zoom: float) -> void:
	var clean_zoom: float = clampf(snappedf(next_zoom, PDF_ZOOM_STEP), PDF_ZOOM_MIN, PDF_ZOOM_MAX)
	if is_equal_approx(clean_zoom, _pdf_zoom):
		return
	_pdf_zoom = clean_zoom
	_update_pdf_geometry()
	_request_pdf_page()
	_refresh_pdf_controls()


func _on_pdf_zoom_out() -> void:
	_set_pdf_zoom(_pdf_zoom - PDF_ZOOM_STEP)


func _on_pdf_zoom_in() -> void:
	_set_pdf_zoom(_pdf_zoom + PDF_ZOOM_STEP)


func _on_pdf_zoom_reset() -> void:
	_set_pdf_zoom(PDF_ZOOM_MIN)


func _on_pdf_document_ready(changed_asset_id: String, _metadata: Dictionary) -> void:
	if changed_asset_id != _asset_id or _kind != AssetKinds.PDF or _pdf_media == null:
		return
	_pdf_page_count = maxi(0, _pdf_media.get_page_count(_asset_id))
	_pdf_page_index = clampi(_pdf_page_index, 0, maxi(0, _pdf_page_count - 1))
	_update_pdf_geometry()
	_request_pdf_page()


func _on_pdf_page_ready(changed_asset_id: String, page_index: int) -> void:
	if changed_asset_id != _asset_id or page_index != _pdf_page_index or _kind != AssetKinds.PDF:
		return
	_request_pdf_page()


func _on_texture_ready(changed_asset_id: String) -> void:
	if changed_asset_id != _asset_id or _kind != AssetKinds.IMAGE:
		return
	_refresh_image_texture()


func _on_video_thumbnail_ready(changed_asset_id: String) -> void:
	if changed_asset_id != _asset_id or _kind != AssetKinds.VIDEO or _video_poster == null or _video_media == null:
		return
	_video_poster.texture = _video_media.get_thumbnail(_asset_id)
	if _video_poster.texture != null:
		_update_video_aspect_from_texture(_video_poster.texture)
	if _video_placeholder != null:
		_video_placeholder.visible = _video_poster.texture == null


func _on_audio_waveform_ready(changed_asset_id: String) -> void:
	if changed_asset_id != _asset_id or _kind != AssetKinds.AUDIO or _audio_waveform == null or _audio_media == null:
		return
	_audio_waveform.texture = _audio_media.get_waveform(_asset_id, false)


func _on_audio_playback_ready(changed_asset_id: String, _path: String) -> void:
	if changed_asset_id != _asset_id or _kind != AssetKinds.AUDIO:
		return
	if _audio_player == null or _audio_player.stream != null:
		return
	# Do not autoplay a background-prepared stream. The next explicit Play reuses it.
	_ensure_audio_stream()


func _on_library_changed() -> void:
	if _library == null or not NoteResourceEmbed.is_sha256(_hash_sha256):
		return
	var asset: Dictionary = _library.find_asset_by_hash(_hash_sha256)
	if asset.is_empty():
		if not _asset_id.is_empty():
			_refresh()
		return
	var next_asset_id: String = str(asset.get("id", "")).strip_edges()
	var next_kind: int = int(asset.get("kind", AssetKinds.OTHER))
	if next_asset_id != _asset_id or next_kind != _kind:
		_refresh()
		return
	# Metadata-only Library changes must not tear down an active decoder/player.
	# Refresh only the lightweight header while keeping the live surface intact.
	_title_label.text = _caption if not _caption.is_empty() else str(asset.get("display_name", _asset_id))
	_meta_label.text = NotLightL10n.text("ui.format.hash_metadata") % [
		AssetKinds.label(_kind),
		_format_bytes(int(asset.get("byte_size", 0))),
		_hash_summary(),
	]


func _connect_services() -> void:
	if _image_cache != null and not _image_cache.texture_ready.is_connected(_on_texture_ready):
		_image_cache.texture_ready.connect(_on_texture_ready)
	if _library != null and not _library.library_changed.is_connected(_on_library_changed):
		_library.library_changed.connect(_on_library_changed)
	if _video_media != null and not _video_media.thumbnail_ready.is_connected(_on_video_thumbnail_ready):
		_video_media.thumbnail_ready.connect(_on_video_thumbnail_ready)
	if _audio_media != null:
		if not _audio_media.waveform_ready.is_connected(_on_audio_waveform_ready):
			_audio_media.waveform_ready.connect(_on_audio_waveform_ready)
		if not _audio_media.playback_ready.is_connected(_on_audio_playback_ready):
			_audio_media.playback_ready.connect(_on_audio_playback_ready)
	if _pdf_media != null:
		if not _pdf_media.document_ready.is_connected(_on_pdf_document_ready):
			_pdf_media.document_ready.connect(_on_pdf_document_ready)
		if not _pdf_media.page_ready.is_connected(_on_pdf_page_ready):
			_pdf_media.page_ready.connect(_on_pdf_page_ready)


func _disconnect_services() -> void:
	if _image_cache != null and _image_cache.texture_ready.is_connected(_on_texture_ready):
		_image_cache.texture_ready.disconnect(_on_texture_ready)
	if _library != null and _library.library_changed.is_connected(_on_library_changed):
		_library.library_changed.disconnect(_on_library_changed)
	if _video_media != null and _video_media.thumbnail_ready.is_connected(_on_video_thumbnail_ready):
		_video_media.thumbnail_ready.disconnect(_on_video_thumbnail_ready)
	if _audio_media != null:
		if _audio_media.waveform_ready.is_connected(_on_audio_waveform_ready):
			_audio_media.waveform_ready.disconnect(_on_audio_waveform_ready)
		if _audio_media.playback_ready.is_connected(_on_audio_playback_ready):
			_audio_media.playback_ready.disconnect(_on_audio_playback_ready)
	if _pdf_media != null:
		if _pdf_media.document_ready.is_connected(_on_pdf_document_ready):
			_pdf_media.document_ready.disconnect(_on_pdf_document_ready)
		if _pdf_media.page_ready.is_connected(_on_pdf_page_ready):
			_pdf_media.page_ready.disconnect(_on_pdf_page_ready)


func _on_image_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and mouse.double_click:
			_request_preview()
			accept_event()


func _request_preview() -> void:
	if not _asset_id.is_empty():
		preview_requested.emit(_asset_id)


func _hash_summary() -> String:
	return _hash_sha256.left(12) if not _hash_sha256.is_empty() else NotLightL10n.text("performance.unavailable")


func _format_bytes(value: int) -> String:
	var bytes: float = float(maxi(0, value))
	if bytes < 1024.0:
		return NotLightL10n.text("ui.format.bytes_b") % int(bytes)
	if bytes < 1024.0 * 1024.0:
		return NotLightL10n.text("ui.format.bytes_kb") % (bytes / 1024.0)
	if bytes < 1024.0 * 1024.0 * 1024.0:
		return NotLightL10n.text("ui.format.bytes_mb") % (bytes / (1024.0 * 1024.0))
	return NotLightL10n.text("ui.format.bytes_gb") % (bytes / (1024.0 * 1024.0 * 1024.0))


func _time_text(position: float, duration: float) -> String:
	return NotLightL10n.text("ui.format.media_time_pair") % [_clock(position), _clock(duration)] if duration > 0.0 else _clock(position)


func _clock(seconds: float) -> String:
	var safe_seconds: int = maxi(0, int(floor(seconds)))
	var minutes: int = int(safe_seconds / 60)
	var remainder: int = safe_seconds % 60
	return NotLightL10n.text("ui.format.duration_minutes") % [minutes, remainder]
