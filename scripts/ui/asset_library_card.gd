# SPDX-License-Identifier: GPL-3.0-or-later
class_name AssetLibraryCard
extends PanelContainer

signal rename_requested(asset_id: String, current_name: String)
signal move_requested(asset_id: String)
signal delete_requested(asset_id: String, display_name: String, usage_count: int)
signal insert_requested(asset_id: String)
signal workspace_insert_requested(asset_id: String)
signal message_requested(message: String)
signal inspect_requested(asset_id: String)
signal preview_requested(asset_id: String)
signal bulk_select_requested(asset_id: String, toggle: bool, range_select: bool)

const MENU_PREVIEW: int = 0
const MENU_RENAME: int = 1
const MENU_MOVE: int = 2
const MENU_DELETE: int = 3
const MENU_COPY_NOTE_EMBED: int = 4
const MENU_VIDEO_OPTIMIZE: int = 20
const MENU_VIDEO_USE_ORIGINAL: int = 21
const MENU_VIDEO_USE_OPTIMIZED: int = 22
const MENU_VIDEO_DELETE_ORIGINAL: int = 23
const MENU_VIDEO_DELETE_OPTIMIZED: int = 24
const MENU_AUDIO_OPTIMIZE: int = 30
const MENU_AUDIO_USE_ORIGINAL: int = 31
const MENU_AUDIO_USE_OPTIMIZED: int = 32
const MENU_AUDIO_DELETE_ORIGINAL: int = 33
const MENU_AUDIO_DELETE_OPTIMIZED: int = 34
const MENU_PDF_OPTIMIZE_LOSSLESS: int = 40
const MENU_PDF_OPTIMIZE_BALANCED: int = 41
const MENU_PDF_CANCEL_OPTIMIZATION: int = 42
const MENU_PDF_USE_ORIGINAL: int = 43
const MENU_PDF_USE_OPTIMIZED: int = 44
const MENU_PDF_DELETE_OPTIMIZED: int = 45

var asset_id: String = ""
var _name_label: Label
var _kind_label: Label
var _meta_label: Label
var _usage_label: Label
var _preview_texture: TextureRect
var _preview_fallback: CenterContainer
var _insert_button: Button
var _workspace_insert_button: Button
var _menu: PopupMenu
var _display_name: String = ""
var _usage_count: int = 0
var _board_usage_count: int = 0
var _note_usage_count: int = 0
var _feature_usage_count: int = 0
var _kind: int = AssetKinds.OTHER
var _hash_sha256: String = ""
var _delete_menu_index: int = -1
var _cache: ImageAssetCache
var _video_media: VideoMediaService
var _audio_media: AudioMediaService
var _pdf_media: PdfMediaService
var _pdf_optimizer: PdfOptimizationService
var _allow_destructive_variants: bool = true
var _allow_bulk_selection: bool = false
var _selection_toggle: CheckBox


func _ready() -> void:
	theme_type_variation = "AssetCardPanel"
	custom_minimum_size = Vector2(228.0, 200.0)
	focus_mode = Control.FOCUS_ALL
	gui_input.connect(_on_card_gui_input)
	_build_ui()



func set_selected(selected: bool) -> void:
	theme_type_variation = "AssetCardSelectedPanel" if selected else "AssetCardPanel"


func _on_card_gui_input(event: InputEvent) -> void:
	if asset_id.is_empty():
		return
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_event.double_click:
			preview_requested.emit(asset_id)
			accept_event()
			return
		if _allow_bulk_selection and (mouse_event.ctrl_pressed or mouse_event.meta_pressed or mouse_event.shift_pressed):
			bulk_select_requested.emit(asset_id, mouse_event.ctrl_pressed or mouse_event.meta_pressed, mouse_event.shift_pressed)
			accept_event()
			return
		inspect_requested.emit(asset_id)
	elif event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		if key_event.keycode == KEY_ENTER:
			preview_requested.emit(asset_id)
			accept_event()
		elif key_event.keycode == KEY_SPACE:
			if _allow_bulk_selection:
				bulk_select_requested.emit(asset_id, true, false)
			else:
				inspect_requested.emit(asset_id)
			accept_event()

func configure(
	record: Dictionary,
	allow_delete: bool = true,
	allow_insert: bool = false,
	image_cache: ImageAssetCache = null,
	video_media: VideoMediaService = null,
	audio_media: AudioMediaService = null,
	pdf_media: PdfMediaService = null,
	pdf_optimizer: PdfOptimizationService = null,
	allow_bulk_selection: bool = false
) -> void:
	asset_id = str(record.get("id", ""))
	_display_name = str(record.get("display_name", NotLightL10n.text("library.resource")))
	_usage_count = int(record.get("usage_count", 0))
	_board_usage_count = int(record.get("board_usage_count", 0))
	_note_usage_count = int(record.get("note_embed_usage_count", 0))
	_feature_usage_count = int(record.get("feature_usage_count", 0))
	_kind = int(record.get("kind", AssetKinds.OTHER))
	_hash_sha256 = str(record.get("hash_sha256", "")).strip_edges().to_lower()
	_cache = image_cache
	_video_media = video_media
	_audio_media = audio_media
	_pdf_media = pdf_media
	_pdf_optimizer = pdf_optimizer
	_allow_destructive_variants = allow_delete
	_allow_bulk_selection = allow_bulk_selection
	if _selection_toggle != null:
		_selection_toggle.visible = allow_bulk_selection
	var extension: String = str(record.get("extension", "")).to_upper()
	var byte_size: int = int(record.get("byte_size", 0))
	_name_label.text = _display_name
	_name_label.tooltip_text = _display_name
	_kind_label.text = NotLightL10n.text("ui.format.kind_symbol") % [AssetKinds.symbol(_kind), AssetKinds.short_label(_kind)]
	_set_meta_text(NotLightL10n.text("ui.format.two_parts") % [extension if not extension.is_empty() else AssetKinds.short_label(AssetKinds.OTHER), _format_bytes(byte_size)])
	if _feature_usage_count > 0:
		NotLightL10n.bind_text(_usage_label, "library.usage.app_feature")
		var other_refs: int = _board_usage_count + _note_usage_count
		if other_refs > 0:
			_usage_label.text += NotLightL10n.text("ui.format.append_middle_dot") % NotLightL10n.text("library.usage.other_refs", {"count": other_refs})
		_usage_label.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
	elif _board_usage_count > 0 and _note_usage_count > 0:
		_usage_label.text = NotLightL10n.text("library.usage.boards_and_notes", {
			"boards": _board_usage_count,
			"notes": _note_usage_count,
		})
		_usage_label.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
	elif _board_usage_count > 0:
		_usage_label.text = NotLightL10n.text("library.usage.boards", {"count": _board_usage_count})
		_usage_label.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
	elif _note_usage_count > 0:
		_usage_label.text = NotLightL10n.text("library.usage.notes", {"count": _note_usage_count})
		_usage_label.add_theme_color_override("font_color", NotLightTheme.semantic_color("accent"))
	else:
		NotLightL10n.bind_text(_usage_label, "library.usage.none")
		_usage_label.add_theme_color_override("font_color", NotLightTheme.semantic_color("text_muted"))
	if _menu != null and _delete_menu_index >= 0:
		_menu.set_item_disabled(_delete_menu_index, not allow_delete)
	var can_insert: bool = allow_insert and AssetKinds.is_board_insertable(_kind)
	_insert_button.visible = can_insert
	if _workspace_insert_button != null:
		_workspace_insert_button.visible = can_insert and _kind == AssetKinds.NOTE
		if _kind == AssetKinds.NOTE:
			NotLightL10n.bind_text(_insert_button, "notes.place_simple_on_board")
			NotLightL10n.bind_tooltip(_insert_button, "notes.place_simple_on_board_hint")
		else:
			NotLightL10n.bind_text(_insert_button, "notes.place_on_board")
	_refresh_preview()
	if _cache != null and not _cache.texture_ready.is_connected(_on_texture_ready):
		_cache.texture_ready.connect(_on_texture_ready)
	if _video_media != null and not _video_media.thumbnail_ready.is_connected(_on_video_thumbnail_ready):
		_video_media.thumbnail_ready.connect(_on_video_thumbnail_ready)
	if _video_media != null and not _video_media.variant_state_changed.is_connected(_on_video_variant_state_changed):
		_video_media.variant_state_changed.connect(_on_video_variant_state_changed)
	if _video_media != null and not _video_media.optimization_progress.is_connected(_on_video_optimization_progress):
		_video_media.optimization_progress.connect(_on_video_optimization_progress)
	if _video_media != null and not _video_media.optimization_failed.is_connected(_on_video_optimization_failed):
		_video_media.optimization_failed.connect(_on_video_optimization_failed)
	if _video_media != null and not _video_media.optimization_completed.is_connected(_on_video_optimization_completed):
		_video_media.optimization_completed.connect(_on_video_optimization_completed)
	if _audio_media != null and not _audio_media.waveform_ready.is_connected(_on_audio_waveform_ready):
		_audio_media.waveform_ready.connect(_on_audio_waveform_ready)
	if _audio_media != null and not _audio_media.variant_state_changed.is_connected(_on_audio_variant_state_changed):
		_audio_media.variant_state_changed.connect(_on_audio_variant_state_changed)
	if _audio_media != null and not _audio_media.optimization_progress.is_connected(_on_audio_optimization_progress):
		_audio_media.optimization_progress.connect(_on_audio_optimization_progress)
	if _audio_media != null and not _audio_media.optimization_failed.is_connected(_on_audio_optimization_failed):
		_audio_media.optimization_failed.connect(_on_audio_optimization_failed)
	if _audio_media != null and not _audio_media.optimization_completed.is_connected(_on_audio_optimization_completed):
		_audio_media.optimization_completed.connect(_on_audio_optimization_completed)
	if _pdf_media != null and not _pdf_media.page_ready.is_connected(_on_pdf_page_ready):
		_pdf_media.page_ready.connect(_on_pdf_page_ready)
	if _pdf_media != null and not _pdf_media.document_ready.is_connected(_on_pdf_document_ready):
		_pdf_media.document_ready.connect(_on_pdf_document_ready)
	if _pdf_media != null and not _pdf_media.variant_state_changed.is_connected(_on_pdf_variant_state_changed):
		_pdf_media.variant_state_changed.connect(_on_pdf_variant_state_changed)
	if _pdf_optimizer != null and not _pdf_optimizer.optimization_progress.is_connected(_on_pdf_optimization_progress):
		_pdf_optimizer.optimization_progress.connect(_on_pdf_optimization_progress)
	if _pdf_optimizer != null and not _pdf_optimizer.optimization_failed.is_connected(_on_pdf_optimization_failed):
		_pdf_optimizer.optimization_failed.connect(_on_pdf_optimization_failed)
	if _pdf_optimizer != null and not _pdf_optimizer.optimization_completed.is_connected(_on_pdf_optimization_completed):
		_pdf_optimizer.optimization_completed.connect(_on_pdf_optimization_completed)
	_refresh_media_menu()
	if _kind == AssetKinds.PDF:
		_refresh_pdf_meta()
	elif _kind == AssetKinds.VIDEO:
		_refresh_video_meta()
	elif _kind == AssetKinds.AUDIO:
		_refresh_audio_meta()


func _build_ui() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_theme_constant_override("separation", 9)
	add_child(root)

	var preview: PanelContainer = PanelContainer.new()
	preview.theme_type_variation = "AssetPreviewPanel"
	preview.mouse_filter = Control.MOUSE_FILTER_PASS
	preview.custom_minimum_size = Vector2(0.0, 92.0)
	preview.clip_contents = true
	root.add_child(preview)

	_preview_texture = TextureRect.new()
	_preview_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(_preview_texture)

	_preview_fallback = CenterContainer.new()
	_preview_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(_preview_fallback)
	_kind_label = Label.new()
	_kind_label.theme_type_variation = "AssetKindLabel"
	_kind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_fallback.add_child(_kind_label)

	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_PASS
	title_row.add_theme_constant_override("separation", 6)
	root.add_child(title_row)
	_name_label = Label.new()
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.theme_type_variation = "SectionLabel"
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(_name_label)
	_selection_toggle = CheckBox.new()
	_selection_toggle.visible = false
	_selection_toggle.focus_mode = Control.FOCUS_NONE
	NotLightL10n.bind_tooltip(_selection_toggle, "library.bulk.toggle")
	_selection_toggle.toggled.connect(_on_selection_toggle_toggled)
	title_row.add_child(_selection_toggle)
	var menu_button: Button = Button.new()
	menu_button.text = "⋯"
	NotLightL10n.bind_tooltip(menu_button, "runtime.ui.asset_library_card.7311fa3a47")
	menu_button.theme_type_variation = "GhostButton"
	menu_button.custom_minimum_size = Vector2(32.0, 30.0)
	menu_button.pressed.connect(_open_menu.bind(menu_button))
	title_row.add_child(menu_button)

	_meta_label = Label.new()
	_meta_label.theme_type_variation = "CaptionLabel"
	_meta_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_meta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_meta_label)
	_usage_label = Label.new()
	_usage_label.theme_type_variation = "CaptionStrongLabel"
	_usage_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_usage_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_usage_label)

	var insert_row: HBoxContainer = HBoxContainer.new()
	insert_row.add_theme_constant_override("separation", 6)
	root.add_child(insert_row)
	_insert_button = Button.new()
	NotLightL10n.bind_text(_insert_button, "notes.place_on_board")
	NotLightL10n.bind_tooltip(_insert_button, "notes.place_simple_on_board_hint")
	_insert_button.theme_type_variation = "PrimaryButton"
	_insert_button.custom_minimum_size = Vector2(0.0, 34.0)
	_insert_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_insert_button.visible = false
	_insert_button.pressed.connect(func() -> void: insert_requested.emit(asset_id))
	insert_row.add_child(_insert_button)
	_workspace_insert_button = Button.new()
	_workspace_insert_button.icon = load("res://assets/icons/workspace.svg") as Texture2D
	_workspace_insert_button.theme_type_variation = "IconButton"
	_workspace_insert_button.custom_minimum_size = Vector2(38.0, 34.0)
	_workspace_insert_button.visible = false
	NotLightL10n.bind_tooltip(_workspace_insert_button, "notes.place_workspace_on_board")
	_workspace_insert_button.pressed.connect(func() -> void: workspace_insert_requested.emit(asset_id))
	insert_row.add_child(_workspace_insert_button)

	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu_pressed)
	add_child(_menu)
	_rebuild_menu()


func set_bulk_selected(selected: bool) -> void:
	if _selection_toggle != null:
		_selection_toggle.set_pressed_no_signal(selected)


func _on_selection_toggle_toggled(_selected: bool) -> void:
	if _allow_bulk_selection and not asset_id.is_empty():
		bulk_select_requested.emit(asset_id, true, false)


func _set_meta_text(value: String) -> void:
	if _meta_label == null:
		return
	_meta_label.text = value


func _refresh_preview() -> void:
	if _preview_texture == null or _preview_fallback == null:
		return
	_preview_texture.texture = null
	_preview_fallback.visible = true
	if asset_id.is_empty():
		return
	var texture: Texture2D = null
	if _kind == AssetKinds.IMAGE and _cache != null:
		texture = _cache.request_texture(asset_id, 240.0)
	elif _kind == AssetKinds.VIDEO and _video_media != null:
		texture = _video_media.get_thumbnail(asset_id)
	elif _kind == AssetKinds.PDF and _pdf_media != null:
		texture = _pdf_media.request_thumbnail(asset_id)
	elif _kind == AssetKinds.AUDIO and _audio_media != null:
		# Resource Library browsing is an explicit media-view operation. Requesting
		# a bounded waveform here is useful UX, while AudioMediaService keeps the
		# request asynchronous/serial and its retained board draw path disk-free.
		texture = _audio_media.get_waveform(asset_id)
	if texture != null:
		_preview_texture.texture = texture
		_preview_fallback.visible = false


func _on_texture_ready(ready_asset_id: String) -> void:
	if ready_asset_id == asset_id:
		_refresh_preview()


func _on_video_thumbnail_ready(ready_asset_id: String) -> void:
	if ready_asset_id == asset_id:
		_refresh_preview()


func _on_audio_waveform_ready(ready_asset_id: String) -> void:
	if ready_asset_id == asset_id:
		_refresh_preview()


func _on_pdf_page_ready(ready_asset_id: String, page_index: int) -> void:
	if ready_asset_id == asset_id and page_index == 0:
		_refresh_preview()


func _on_pdf_document_ready(ready_asset_id: String, _metadata: Dictionary) -> void:
	if ready_asset_id != asset_id:
		return
	_refresh_pdf_meta()
	_refresh_preview()


func _refresh_pdf_meta() -> void:
	if _pdf_media == null or asset_id.is_empty() or _kind != AssetKinds.PDF:
		return
	var info: Dictionary = _pdf_media.get_document_info(asset_id)
	var state: Dictionary = _pdf_media.get_variant_state(asset_id)
	var variants: Dictionary = state.get("variants", {}) as Dictionary
	var original: Dictionary = variants.get(PdfMediaService.VARIANT_ORIGINAL, {}) as Dictionary
	var optimized: Dictionary = variants.get(PdfMediaService.VARIANT_OPTIMIZED, {}) as Dictionary
	var preferred: String = str(state.get("preferred_variant", PdfMediaService.VARIANT_ORIGINAL))
	var parts: PackedStringArray = PackedStringArray()
	var page_count: int = maxi(0, int(info.get("page_count", 0)))
	if page_count > 0:
		parts.append(NotLightL10n.text("library.pdf.meta", {"count": page_count}))
	if not original.is_empty() and _pdf_media.has_variant(asset_id, PdfMediaService.VARIANT_ORIGINAL):
		parts.append(NotLightL10n.text("pdf.variant.original_size", {"size": _format_bytes(int(original.get("byte_size", 0)))}))
	if not optimized.is_empty() and _pdf_media.has_variant(asset_id, PdfMediaService.VARIANT_OPTIMIZED):
		parts.append(NotLightL10n.text("pdf.variant.optimized_size", {"size": _format_bytes(int(optimized.get("byte_size", 0)))}))
		var active_label: String = NotLightL10n.text(
			"pdf.variant.optimized" if preferred == PdfMediaService.VARIANT_OPTIMIZED else "pdf.variant.original"
		)
		parts.append(NotLightL10n.text("pdf.variant.active", {"variant": active_label}))
	if not parts.is_empty():
		_set_meta_text(" · ".join(parts))
	if page_count <= 0:
		_pdf_media.ensure_document(asset_id)


func _on_pdf_variant_state_changed(changed_asset_id: String, _state: Dictionary) -> void:
	if changed_asset_id != asset_id:
		return
	_refresh_pdf_meta()
	_refresh_preview()
	_refresh_media_menu()


func _on_audio_variant_state_changed(changed_asset_id: String, _state: Dictionary) -> void:
	if changed_asset_id != asset_id:
		return
	_refresh_audio_meta()
	_refresh_media_menu()


func _refresh_audio_meta() -> void:
	if _audio_media == null or asset_id.is_empty() or _kind != AssetKinds.AUDIO:
		return
	var state: Dictionary = _audio_media.get_variant_state(asset_id)
	var variants: Dictionary = state.get("variants", {}) as Dictionary
	var original: Dictionary = variants.get(AudioMediaService.VARIANT_ORIGINAL, {}) as Dictionary
	var optimized: Dictionary = variants.get(AudioMediaService.VARIANT_OPTIMIZED, {}) as Dictionary
	var preferred: String = str(state.get("preferred_variant", AudioMediaService.VARIANT_ORIGINAL))
	var parts: PackedStringArray = PackedStringArray()
	if not original.is_empty():
		parts.append(NotLightL10n.text("audio.variant.original_size", {"size": _format_bytes(int(original.get("byte_size", 0)))}))
	if not optimized.is_empty():
		parts.append(NotLightL10n.text("audio.variant.optimized_size", {"size": _format_bytes(int(optimized.get("byte_size", 0)))}))
	if not optimized.is_empty():
		var active_label: String = NotLightL10n.text(
			"audio.variant.optimized" if preferred == AudioMediaService.VARIANT_OPTIMIZED else "audio.variant.original"
		)
		parts.append(NotLightL10n.text("audio.variant.active", {"variant": active_label}))
	if not parts.is_empty():
		_set_meta_text(" · ".join(parts))


func _on_video_variant_state_changed(changed_asset_id: String, _state: Dictionary) -> void:
	if changed_asset_id == asset_id:
		_refresh_video_meta()
		_refresh_media_menu()


func _refresh_video_meta() -> void:
	if _video_media == null or asset_id.is_empty() or _kind != AssetKinds.VIDEO:
		return
	var state: Dictionary = _video_media.get_variant_state(asset_id)
	var variants: Dictionary = state.get("variants", {}) as Dictionary
	var original: Dictionary = variants.get("original", {}) as Dictionary
	var optimized: Dictionary = variants.get("optimized", {}) as Dictionary
	var preferred: String = str(state.get("preferred_variant", "original"))
	var parts: PackedStringArray = PackedStringArray()
	if not original.is_empty():
		parts.append(NotLightL10n.text("runtime.ui.asset_library_card.0fae92c0b5") % _format_bytes(int(original.get("byte_size", 0))))
	if not optimized.is_empty():
		parts.append(NotLightL10n.text("runtime.ui.asset_library_card.cab939aa5e") % _format_bytes(int(optimized.get("byte_size", 0))))
	if not optimized.is_empty():
		parts.append(NotLightL10n.text("runtime.ui.asset_library_card.995c775305") % (NotLightL10n.text("audio.variant.optimized") if preferred == "optimized" else NotLightL10n.text("pdf.variant.original")))
	if not parts.is_empty():
		_set_meta_text(" · ".join(parts))


func _open_menu(button: Button) -> void:
	_refresh_media_menu()
	var global_rect: Rect2 = button.get_global_rect()
	_menu.position = Vector2i(int(global_rect.position.x), int(global_rect.end.y + 4.0))
	_menu.popup()


func _on_menu_pressed(menu_id: int) -> void:
	match menu_id:
		MENU_PREVIEW:
			preview_requested.emit(asset_id)
		MENU_RENAME:
			rename_requested.emit(asset_id, _display_name)
		MENU_MOVE:
			move_requested.emit(asset_id)
		MENU_COPY_NOTE_EMBED:
			var embed_syntax: String = NoteResourceEmbed.syntax_for_hash(_hash_sha256, _display_name)
			if embed_syntax.is_empty():
				message_requested.emit(NotLightL10n.text("notes.embed.copy_failed"))
			else:
				DisplayServer.clipboard_set(embed_syntax)
				message_requested.emit(NotLightL10n.text("notes.embed.copied"))
		MENU_VIDEO_OPTIMIZE:
			if _video_media == null or not _video_media.enqueue_optimization(asset_id, "auto"):
				message_requested.emit(NotLightL10n.text("runtime.ui.asset_library_card.d393291461"))
		MENU_VIDEO_USE_ORIGINAL:
			if _video_media != null and not _video_media.set_preferred_variant(asset_id, VideoMediaService.VARIANT_ORIGINAL):
				message_requested.emit(NotLightL10n.text("runtime.ui.asset_library_card.8ce1bc22b3"))
		MENU_VIDEO_USE_OPTIMIZED:
			if _video_media != null and not _video_media.set_preferred_variant(asset_id, VideoMediaService.VARIANT_OPTIMIZED):
				message_requested.emit(NotLightL10n.text("runtime.ui.asset_library_card.efb76139a4"))
		MENU_VIDEO_DELETE_ORIGINAL:
			if _video_media != null and not _video_media.delete_original_variant(asset_id):
				message_requested.emit(NotLightL10n.text("runtime.ui.asset_library_card.6b1eaa5b28"))
		MENU_VIDEO_DELETE_OPTIMIZED:
			if _video_media != null and not _video_media.delete_optimized_variant(asset_id):
				message_requested.emit(NotLightL10n.text("runtime.ui.video_board_player.cace216651"))
		MENU_AUDIO_OPTIMIZE:
			if _audio_media == null or not _audio_media.enqueue_optimization(asset_id):
				message_requested.emit(NotLightL10n.text("audio.optimize.enqueue_failed"))
		MENU_AUDIO_USE_ORIGINAL:
			if _audio_media != null and not _audio_media.set_preferred_variant(asset_id, AudioMediaService.VARIANT_ORIGINAL):
				message_requested.emit(NotLightL10n.text("audio.variant.original_unavailable"))
		MENU_AUDIO_USE_OPTIMIZED:
			if _audio_media != null and not _audio_media.set_preferred_variant(asset_id, AudioMediaService.VARIANT_OPTIMIZED):
				message_requested.emit(NotLightL10n.text("audio.variant.optimized_unavailable"))
		MENU_AUDIO_DELETE_ORIGINAL:
			if _audio_media != null and not _audio_media.delete_original_variant(asset_id):
				message_requested.emit(NotLightL10n.text("audio.variant.delete_original_failed"))
		MENU_AUDIO_DELETE_OPTIMIZED:
			if _audio_media != null and not _audio_media.delete_optimized_variant(asset_id):
				message_requested.emit(NotLightL10n.text("audio.variant.delete_optimized_failed"))
		MENU_PDF_OPTIMIZE_LOSSLESS:
			if _pdf_optimizer == null:
				message_requested.emit(NotLightL10n.text("pdf.optimize.enqueue_failed"))
			else:
				_pdf_optimizer.enqueue_optimization(asset_id, PdfOptimizationService.PRESET_LOSSLESS)
		MENU_PDF_OPTIMIZE_BALANCED:
			if _pdf_optimizer == null:
				message_requested.emit(NotLightL10n.text("pdf.optimize.enqueue_failed"))
			else:
				_pdf_optimizer.enqueue_optimization(asset_id, PdfOptimizationService.PRESET_BALANCED)
		MENU_PDF_CANCEL_OPTIMIZATION:
			if _pdf_optimizer != null:
				_pdf_optimizer.cancel_optimization(asset_id)
		MENU_PDF_USE_ORIGINAL:
			if _pdf_media != null and not _pdf_media.set_preferred_variant(asset_id, PdfMediaService.VARIANT_ORIGINAL):
				message_requested.emit(NotLightL10n.text("pdf.variant.original_unavailable"))
		MENU_PDF_USE_OPTIMIZED:
			if _pdf_media != null and not _pdf_media.set_preferred_variant(asset_id, PdfMediaService.VARIANT_OPTIMIZED):
				message_requested.emit(NotLightL10n.text("pdf.variant.optimized_unavailable"))
		MENU_PDF_DELETE_OPTIMIZED:
			if _pdf_media != null and not _pdf_media.delete_optimized_variant(asset_id):
				message_requested.emit(NotLightL10n.text("pdf.variant.delete_optimized_failed"))
		MENU_DELETE:
			delete_requested.emit(asset_id, _display_name, _usage_count)
	_refresh_media_menu()


func _rebuild_menu() -> void:
	if _menu == null:
		return
	_menu.clear()
	if AssetKinds.is_previewable(_kind):
		_menu.add_item(NotLightL10n.text("library.preview.action"), MENU_PREVIEW)
		_menu.add_separator()
	_menu.add_item(NotLightL10n.text("common.rename"), MENU_RENAME)
	_menu.add_item(NotLightL10n.text("runtime.ui.asset_library_card.2734f155de"), MENU_MOVE)
	if NoteResourceEmbed.is_embeddable_kind(_kind) and NoteResourceEmbed.is_sha256(_hash_sha256):
		_menu.add_item(NotLightL10n.text("notes.embed.copy_action"), MENU_COPY_NOTE_EMBED)

	var is_video: bool = _kind == AssetKinds.VIDEO and _video_media != null
	if is_video:
		_menu.add_separator()
		_menu.add_item(NotLightL10n.text("runtime.ui.asset_library_card.073af0d792"), MENU_VIDEO_OPTIMIZE)
		_menu.add_radio_check_item(NotLightL10n.text("pdf.menu.use_original"), MENU_VIDEO_USE_ORIGINAL)
		_menu.add_radio_check_item(NotLightL10n.text("audio.menu.use_optimized"), MENU_VIDEO_USE_OPTIMIZED)
		_menu.add_separator()
		_menu.add_item(NotLightL10n.text("audio.menu.delete_original"), MENU_VIDEO_DELETE_ORIGINAL)
		_menu.add_item(NotLightL10n.text("audio.menu.delete_optimized"), MENU_VIDEO_DELETE_OPTIMIZED)

	var is_audio: bool = _kind == AssetKinds.AUDIO and _audio_media != null
	if is_audio:
		_menu.add_separator()
		_menu.add_item(NotLightL10n.text("audio.menu.optimize"), MENU_AUDIO_OPTIMIZE)
		_menu.add_radio_check_item(NotLightL10n.text("audio.menu.use_original"), MENU_AUDIO_USE_ORIGINAL)
		_menu.add_radio_check_item(NotLightL10n.text("audio.menu.use_optimized"), MENU_AUDIO_USE_OPTIMIZED)
		_menu.add_separator()
		_menu.add_item(NotLightL10n.text("audio.menu.delete_original"), MENU_AUDIO_DELETE_ORIGINAL)
		_menu.add_item(NotLightL10n.text("audio.menu.delete_optimized"), MENU_AUDIO_DELETE_OPTIMIZED)

	var is_pdf: bool = _kind == AssetKinds.PDF and _pdf_media != null
	if is_pdf:
		_menu.add_separator()
		_menu.add_item(NotLightL10n.text("pdf.menu.optimize_lossless"), MENU_PDF_OPTIMIZE_LOSSLESS)
		_menu.add_item(NotLightL10n.text("pdf.menu.optimize_balanced"), MENU_PDF_OPTIMIZE_BALANCED)
		_menu.add_item(NotLightL10n.text("pdf.menu.cancel_optimization"), MENU_PDF_CANCEL_OPTIMIZATION)
		_menu.add_separator()
		_menu.add_radio_check_item(NotLightL10n.text("pdf.menu.use_original"), MENU_PDF_USE_ORIGINAL)
		_menu.add_radio_check_item(NotLightL10n.text("pdf.menu.use_optimized"), MENU_PDF_USE_OPTIMIZED)
		_menu.add_item(NotLightL10n.text("pdf.menu.delete_optimized"), MENU_PDF_DELETE_OPTIMIZED)

	_menu.add_separator()
	_delete_menu_index = _menu.item_count
	_menu.add_item(NotLightL10n.text("runtime.ui.asset_library_card.72881e870b"), MENU_DELETE)
	_menu.set_item_disabled(_delete_menu_index, not _allow_destructive_variants)


func _refresh_media_menu() -> void:
	if _menu == null:
		return
	_rebuild_menu()
	if asset_id.is_empty():
		return

	if _kind == AssetKinds.VIDEO and _video_media != null:
		var has_original: bool = _video_media.has_variant(asset_id, VideoMediaService.VARIANT_ORIGINAL)
		var has_optimized: bool = _video_media.has_variant(asset_id, VideoMediaService.VARIANT_OPTIMIZED)
		var preferred: String = _video_media.preferred_variant(asset_id)
		var original_index: int = _menu.get_item_index(MENU_VIDEO_USE_ORIGINAL)
		var optimized_index: int = _menu.get_item_index(MENU_VIDEO_USE_OPTIMIZED)
		var delete_original_index: int = _menu.get_item_index(MENU_VIDEO_DELETE_ORIGINAL)
		var delete_optimized_index: int = _menu.get_item_index(MENU_VIDEO_DELETE_OPTIMIZED)
		if original_index >= 0:
			_menu.set_item_disabled(original_index, not has_original)
			_menu.set_item_checked(original_index, preferred == VideoMediaService.VARIANT_ORIGINAL)
		if optimized_index >= 0:
			_menu.set_item_disabled(optimized_index, not has_optimized)
			_menu.set_item_checked(optimized_index, preferred == VideoMediaService.VARIANT_OPTIMIZED)
		if delete_original_index >= 0:
			_menu.set_item_disabled(delete_original_index, (not _allow_destructive_variants) or not (has_original and has_optimized))
		if delete_optimized_index >= 0:
			_menu.set_item_disabled(delete_optimized_index, (not _allow_destructive_variants) or not (has_original and has_optimized))
		return

	if _kind == AssetKinds.AUDIO and _audio_media != null:
		var has_original: bool = _audio_media.has_variant(asset_id, AudioMediaService.VARIANT_ORIGINAL)
		var has_optimized: bool = _audio_media.has_variant(asset_id, AudioMediaService.VARIANT_OPTIMIZED)
		var preferred: String = _audio_media.preferred_variant(asset_id)
		var optimize_index: int = _menu.get_item_index(MENU_AUDIO_OPTIMIZE)
		var original_index: int = _menu.get_item_index(MENU_AUDIO_USE_ORIGINAL)
		var optimized_index: int = _menu.get_item_index(MENU_AUDIO_USE_OPTIMIZED)
		var delete_original_index: int = _menu.get_item_index(MENU_AUDIO_DELETE_ORIGINAL)
		var delete_optimized_index: int = _menu.get_item_index(MENU_AUDIO_DELETE_OPTIMIZED)
		var optimizing: bool = _audio_media.is_optimizing(asset_id)
		if optimize_index >= 0:
			_menu.set_item_disabled(optimize_index, optimizing or not has_original)
		if original_index >= 0:
			_menu.set_item_disabled(original_index, not has_original)
			_menu.set_item_checked(original_index, preferred == AudioMediaService.VARIANT_ORIGINAL)
		if optimized_index >= 0:
			_menu.set_item_disabled(optimized_index, not has_optimized)
			_menu.set_item_checked(optimized_index, preferred == AudioMediaService.VARIANT_OPTIMIZED)
		if delete_original_index >= 0:
			_menu.set_item_disabled(delete_original_index, optimizing or (not _allow_destructive_variants) or not (has_original and has_optimized))
		if delete_optimized_index >= 0:
			_menu.set_item_disabled(delete_optimized_index, optimizing or (not _allow_destructive_variants) or not (has_original and has_optimized))
		return

	if _kind == AssetKinds.PDF and _pdf_media != null:
		var has_original: bool = _pdf_media.has_variant(asset_id, PdfMediaService.VARIANT_ORIGINAL)
		var has_optimized: bool = _pdf_media.has_variant(asset_id, PdfMediaService.VARIANT_OPTIMIZED)
		var preferred: String = _pdf_media.preferred_variant(asset_id)
		var optimizing: bool = _pdf_optimizer != null and _pdf_optimizer.is_optimizing(asset_id)
		var lossless_index: int = _menu.get_item_index(MENU_PDF_OPTIMIZE_LOSSLESS)
		var balanced_index: int = _menu.get_item_index(MENU_PDF_OPTIMIZE_BALANCED)
		var cancel_index: int = _menu.get_item_index(MENU_PDF_CANCEL_OPTIMIZATION)
		var original_index: int = _menu.get_item_index(MENU_PDF_USE_ORIGINAL)
		var optimized_index: int = _menu.get_item_index(MENU_PDF_USE_OPTIMIZED)
		var delete_optimized_index: int = _menu.get_item_index(MENU_PDF_DELETE_OPTIMIZED)
		if lossless_index >= 0:
			_menu.set_item_disabled(lossless_index, optimizing or not has_original)
		if balanced_index >= 0:
			_menu.set_item_disabled(balanced_index, optimizing or not has_original)
		if cancel_index >= 0:
			_menu.set_item_disabled(cancel_index, not optimizing)
		if original_index >= 0:
			_menu.set_item_disabled(original_index, not has_original)
			_menu.set_item_checked(original_index, preferred == PdfMediaService.VARIANT_ORIGINAL)
		if optimized_index >= 0:
			_menu.set_item_disabled(optimized_index, not has_optimized)
			_menu.set_item_checked(optimized_index, preferred == PdfMediaService.VARIANT_OPTIMIZED)
		if delete_optimized_index >= 0:
			_menu.set_item_disabled(delete_optimized_index, optimizing or (not _allow_destructive_variants) or not has_optimized)


func _on_video_optimization_progress(changed_asset_id: String, progress: float, _message: String) -> void:
	if changed_asset_id != asset_id:
		return
	_set_meta_text(NotLightL10n.text("runtime.ui.asset_library_card.c340d59dc5") % int(round(progress * 100.0)))


func _on_video_optimization_failed(changed_asset_id: String, message: String) -> void:
	if changed_asset_id != asset_id:
		return
	_refresh_video_meta()
	message_requested.emit(message)


func _on_video_optimization_completed(changed_asset_id: String, _optimized_path: String, _saved_bytes: int) -> void:
	if changed_asset_id != asset_id:
		return
	_refresh_video_meta()
	_refresh_media_menu()


func _on_audio_optimization_progress(changed_asset_id: String, progress: float, _message: String) -> void:
	if changed_asset_id != asset_id:
		return
	_set_meta_text(NotLightL10n.text("audio.optimize.card_progress", {"percent": int(round(progress * 100.0))}))


func _on_audio_optimization_failed(changed_asset_id: String, message: String) -> void:
	if changed_asset_id != asset_id:
		return
	_refresh_audio_meta()
	_refresh_media_menu()
	if not message.is_empty():
		message_requested.emit(message)


func _on_audio_optimization_completed(changed_asset_id: String, _optimized_path: String, _saved_bytes: int) -> void:
	if changed_asset_id != asset_id:
		return
	_refresh_audio_meta()
	_refresh_media_menu()


func _on_pdf_optimization_progress(changed_asset_id: String, _progress: float, message: String) -> void:
	if changed_asset_id != asset_id:
		return
	_set_meta_text(message)
	_refresh_media_menu()


func _on_pdf_optimization_failed(changed_asset_id: String, message: String) -> void:
	if changed_asset_id != asset_id:
		return
	_refresh_pdf_meta()
	_refresh_media_menu()
	if not message.is_empty():
		message_requested.emit(message)


func _on_pdf_optimization_completed(changed_asset_id: String, _optimized_path: String, _saved_bytes: int) -> void:
	if changed_asset_id != asset_id:
		return
	_refresh_pdf_meta()
	_refresh_preview()
	_refresh_media_menu()


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
