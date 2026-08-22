# SPDX-License-Identifier: GPL-3.0-or-later
class_name FormulaEditorPanel
extends PanelContainer

signal apply_requested(record: Dictionary)
signal canceled
signal color_picker_requested(anchor_rect: Rect2, current_color: Color)
signal editor_visibility_changed(active: bool)

const PREVIEW_EXTENT: float = 512.0
const DEBOUNCE_SECONDS: float = 0.42

var _service: FormulaRenderService
var _source_edit: TextEdit
var _mode_option: OptionButton
var _scale_slider: HSlider
var _scale_label: Label
var _color_button: Button
var _current_color: Color = FormulaStore.DEFAULT_FOREGROUND
var _preview: TextureRect
var _status: Label
var _details_button: Button
var _details: Label
var _apply_button: Button
var _title: Label
var _debounce_timer: Timer
var _syncing: bool = false
var _is_new: bool = false
var _current_cache_key: String = ""
var _last_error_detail: String = ""
var _preview_token: int = 0


func _ready() -> void:
	theme_type_variation = "FloatingPanel"
	z_index = 430
	visible = false
	custom_minimum_size = Vector2(420.0, 0.0)
	set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	offset_left = -444.0
	offset_top = -280.0
	offset_right = -18.0
	offset_bottom = 280.0
	_build_ui()
	_debounce_timer = Timer.new()
	_debounce_timer.one_shot = true
	_debounce_timer.wait_time = DEBOUNCE_SECONDS
	_debounce_timer.timeout.connect(_request_preview)
	add_child(_debounce_timer)


func configure(service: FormulaRenderService) -> void:
	if _service != null:
		if _service.texture_ready.is_connected(_on_texture_ready):
			_service.texture_ready.disconnect(_on_texture_ready)
		if _service.render_failed.is_connected(_on_render_failed):
			_service.render_failed.disconnect(_on_render_failed)
		if _service.backend_status_changed.is_connected(_on_backend_status_changed):
			_service.backend_status_changed.disconnect(_on_backend_status_changed)
	_service = service
	if _service != null:
		_service.texture_ready.connect(_on_texture_ready)
		_service.render_failed.connect(_on_render_failed)
		_service.backend_status_changed.connect(_on_backend_status_changed)
	_refresh_backend_status()


func open_editor(record: Dictionary, is_new: bool) -> void:
	_is_new = is_new
	_syncing = true
	var normalized: Dictionary = FormulaRenderService.normalize_record(record)
	_source_edit.text = str(normalized.get("source_latex", ""))
	_select_mode(int(normalized.get("display_mode", FormulaStore.DEFAULT_DISPLAY_MODE)))
	_scale_slider.value = float(normalized.get("font_scale", FormulaStore.DEFAULT_FONT_SCALE))
	_scale_label.text = NotLightL10n.text("ui.format.scale_two_decimals") % _scale_slider.value
	var color_value: Variant = normalized.get("foreground", FormulaStore.DEFAULT_FOREGROUND)
	_current_color = color_value if color_value is Color else FormulaStore.DEFAULT_FOREGROUND
	_update_color_button()
	_update_preview_tint()
	_title.text = NotLightL10n.text("formula.editor.new_title") if is_new else NotLightL10n.text("formula.editor.edit_title")
	_apply_button.text = NotLightL10n.text("formula.editor.insert") if is_new else NotLightL10n.text("common.save")
	_details.visible = false
	_details_button.visible = false
	_last_error_detail = ""
	_current_cache_key = ""
	_preview_token += 1
	_preview.texture = null
	_syncing = false
	visible = true
	editor_visibility_changed.emit(true)
	_source_edit.grab_focus()
	_source_edit.set_caret_line(_source_edit.get_line_count() - 1)
	_source_edit.set_caret_column(_source_edit.get_line(_source_edit.get_caret_line()).length())
	_schedule_preview(true)


func close_editor() -> void:
	visible = false
	editor_visibility_changed.emit(false)
	_current_cache_key = ""
	_last_error_detail = ""
	if _debounce_timer != null:
		_debounce_timer.stop()


func current_record() -> Dictionary:
	return {
		"source_latex": FormulaStore.normalize_source(_source_edit.text),
		"display_mode": _mode_option.get_selected_id(),
		"font_scale": float(_scale_slider.value),
		"foreground": _current_color,
	}


func _build_ui() -> void:
	# Keep the compact editor usable at the 960×640 minimum window and with long
	# compiler diagnostics. The panel itself stays fixed while its content scrolls;
	# this avoids the same minimum-size overflow class that previously affected the
	# Resource Library inspector.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	scroll.follow_focus = true
	add_child(scroll)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 9)
	scroll.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)
	_title = Label.new()
	NotLightL10n.bind_text(_title, "formula.editor.new_title")
	_title.theme_type_variation = "SectionTitleLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close_button: Button = Button.new()
	close_button.text = "×"
	NotLightL10n.bind_tooltip(close_button, "common.close")
	close_button.theme_type_variation = "IconButton"
	close_button.custom_minimum_size = Vector2(34.0, 34.0)
	close_button.pressed.connect(_cancel)
	header.add_child(close_button)

	var hint: Label = Label.new()
	NotLightL10n.bind_text(hint, "formula.editor.hint")
	hint.theme_type_variation = "CaptionLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)

	_source_edit = TextEdit.new()
	_source_edit.theme_type_variation = "FormulaSourceEdit"
	_source_edit.custom_minimum_size = Vector2(0.0, 124.0)
	NotLightL10n.bind_placeholder_text(_source_edit, "formula.editor.placeholder")
	_source_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_source_edit.text_changed.connect(_on_source_changed)
	root.add_child(_source_edit)

	var options: HFlowContainer = HFlowContainer.new()
	options.add_theme_constant_override("h_separation", 8)
	options.add_theme_constant_override("v_separation", 6)
	root.add_child(options)
	_mode_option = OptionButton.new()
	_mode_option.custom_minimum_size = Vector2(136.0, 38.0)
	_mode_option.add_item(NotLightL10n.text("formula.mode.inline"), FormulaStore.DISPLAY_INLINE)
	_mode_option.add_item(NotLightL10n.text("formula.mode.block"), FormulaStore.DISPLAY_BLOCK)
	_mode_option.item_selected.connect(_on_option_changed)
	options.add_child(_mode_option)
	_color_button = Button.new()
	_color_button.custom_minimum_size = Vector2(64.0, 38.0)
	NotLightL10n.bind_tooltip(_color_button, "formula.editor.color")
	_color_button.focus_mode = Control.FOCUS_NONE
	_color_button.pressed.connect(func() -> void:
		color_picker_requested.emit(_color_button.get_global_rect(), _current_color)
	)
	options.add_child(_color_button)
	_update_color_button()

	var scale_row: HBoxContainer = HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 8)
	root.add_child(scale_row)
	var scale_title: Label = Label.new()
	NotLightL10n.bind_text(scale_title, "formula.editor.scale")
	scale_title.theme_type_variation = "CaptionStrongLabel"
	scale_row.add_child(scale_title)
	_scale_slider = HSlider.new()
	_scale_slider.scrollable = false
	_scale_slider.min_value = FormulaStore.MIN_FONT_SCALE
	_scale_slider.max_value = FormulaStore.MAX_FONT_SCALE
	_scale_slider.step = 0.05
	_scale_slider.value = FormulaStore.DEFAULT_FONT_SCALE
	_scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scale_slider.value_changed.connect(_on_scale_changed)
	scale_row.add_child(_scale_slider)
	_scale_label = Label.new()
	_scale_label.text = NotLightL10n.text("ui.format.scale_two_decimals") % 1.0
	_scale_label.custom_minimum_size = Vector2(52.0, 0.0)
	_scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scale_row.add_child(_scale_label)

	var preview_panel: PanelContainer = PanelContainer.new()
	preview_panel.theme_type_variation = "SoftPanel"
	preview_panel.custom_minimum_size = Vector2(0.0, 132.0)
	preview_panel.clip_contents = true
	root.add_child(preview_panel)
	var preview_center: CenterContainer = CenterContainer.new()
	preview_panel.add_child(preview_center)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.custom_minimum_size = Vector2(340.0, 112.0)
	preview_center.add_child(_preview)

	_status = Label.new()
	_status.theme_type_variation = "CaptionLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	_details_button = Button.new()
	NotLightL10n.bind_text(_details_button, "formula.editor.details")
	_details_button.theme_type_variation = "GhostButton"
	_details_button.visible = false
	_details_button.pressed.connect(func() -> void: _details.visible = not _details.visible)
	root.add_child(_details_button)
	_details = Label.new()
	_details.theme_type_variation = "CaptionLabel"
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.visible = false
	root.add_child(_details)

	var actions: HFlowContainer = HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 6)
	root.add_child(actions)
	var copy_button: Button = Button.new()
	NotLightL10n.bind_text(copy_button, "formula.editor.copy_latex")
	copy_button.theme_type_variation = "GhostButton"
	copy_button.pressed.connect(_copy_latex)
	actions.add_child(copy_button)
	var cancel_button: Button = Button.new()
	NotLightL10n.bind_text(cancel_button, "common.cancel")
	cancel_button.theme_type_variation = "GhostButton"
	cancel_button.pressed.connect(_cancel)
	actions.add_child(cancel_button)
	_apply_button = Button.new()
	NotLightL10n.bind_text(_apply_button, "formula.editor.insert")
	_apply_button.theme_type_variation = "PrimaryButton"
	_apply_button.pressed.connect(_apply)
	actions.add_child(_apply_button)


func _on_source_changed() -> void:
	if _syncing:
		return
	if _source_edit.text.length() > FormulaStore.MAX_SOURCE_LENGTH:
		_syncing = true
		_source_edit.text = FormulaStore.normalize_source(_source_edit.text)
		_source_edit.set_caret_line(_source_edit.get_line_count() - 1)
		_source_edit.set_caret_column(_source_edit.get_line(_source_edit.get_caret_line()).length())
		_syncing = false
	_schedule_preview()


func _on_option_changed(_index: int) -> void:
	if not _syncing:
		_schedule_preview()


func _on_scale_changed(value: float) -> void:
	_scale_label.text = NotLightL10n.text("ui.format.scale_two_decimals") % value
	if not _syncing:
		_schedule_preview()


func apply_color_from_popover(color: Color) -> void:
	var normalized: Color = Color(color.r, color.g, color.b, 1.0)
	if normalized.to_html(false) == _current_color.to_html(false):
		return
	_current_color = normalized
	_update_color_button()
	_update_preview_tint()


func _update_preview_tint() -> void:
	if _preview != null:
		_preview.modulate = Color(_current_color.r, _current_color.g, _current_color.b, 1.0)


func _update_color_button() -> void:
	if _color_button == null:
		return
	_color_button.text = NotLightL10n.text("ui.format.hex_color") % _current_color.to_html(false).to_upper()
	var border: Color = NotLightTheme.semantic_color("border_strong")
	var normal: StyleBoxFlat = _color_swatch_style(_current_color, border)
	var hover: StyleBoxFlat = _color_swatch_style(_current_color.lightened(0.06), NotLightTheme.semantic_color("accent"))
	var pressed: StyleBoxFlat = _color_swatch_style(_current_color.darkened(0.04), NotLightTheme.semantic_color("accent"))
	_color_button.add_theme_stylebox_override("normal", normal)
	_color_button.add_theme_stylebox_override("hover", hover)
	_color_button.add_theme_stylebox_override("pressed", pressed)
	_color_button.add_theme_stylebox_override("hover_pressed", pressed)
	var luminance: float = 0.2126 * _current_color.r + 0.7152 * _current_color.g + 0.0722 * _current_color.b
	var text_color: Color = Color("#172019") if luminance > 0.58 else Color("#fffdf7")
	_color_button.add_theme_color_override("font_color", text_color)
	_color_button.add_theme_color_override("font_hover_color", text_color)
	_color_button.add_theme_color_override("font_pressed_color", text_color)


func _color_swatch_style(color: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


func _schedule_preview(immediate: bool = false) -> void:
	if not visible or _debounce_timer == null:
		return
	_debounce_timer.stop()
	if immediate:
		_request_preview()
	else:
		NotLightL10n.bind_text(_status, "formula.editor.waiting")
		_debounce_timer.start()


func _request_preview() -> void:
	_preview.texture = null
	_update_preview_tint()
	_details.visible = false
	_details_button.visible = false
	_last_error_detail = ""
	if _service == null:
		NotLightL10n.bind_text(_status, "formula.backend.unavailable")
		return
	var record: Dictionary = current_record()
	if str(record.get("source_latex", "")).strip_edges().is_empty():
		_current_cache_key = ""
		NotLightL10n.bind_text(_status, "formula.editor.empty_preview")
		return
	_status.text = _service.backend_status_text() if not _service.backend_available() else NotLightL10n.text("formula.editor.rendering")
	_preview_token += 1
	var texture: Texture2D = _service.request_preview_texture(record, PREVIEW_EXTENT, _preview_token)
	_current_cache_key = _service.cache_key_for_record(record, PREVIEW_EXTENT)
	if texture != null:
		_preview.texture = texture
		_update_preview_tint()
		NotLightL10n.bind_text(_status, "formula.editor.ready")
	elif not _current_cache_key.is_empty():
		# Deterministic failures are sticky by cache key to prevent hot retry loops.
		# Surface an existing failure immediately when reopening the same formula.
		var cached_failure: String = _service.get_failure_message(_current_cache_key)
		if not cached_failure.is_empty():
			var cached_detail: String = _service.get_failure_detail(_current_cache_key)
			_on_render_failed(_current_cache_key, cached_failure, cached_detail)


func _on_texture_ready(cache_key: String) -> void:
	if not visible:
		return
	if _current_cache_key.is_empty():
		_current_cache_key = _service.cache_key_for_record(current_record(), PREVIEW_EXTENT) if _service != null else ""
	if cache_key != _current_cache_key or _service == null:
		return
	var texture: Texture2D = _service.get_cached_texture(current_record(), PREVIEW_EXTENT)
	if texture != null:
		_preview.texture = texture
		_update_preview_tint()
		NotLightL10n.bind_text(_status, "formula.editor.ready")
		_details_button.visible = false
		_details.visible = false


func _on_render_failed(cache_key: String, message: String, detail: String) -> void:
	if not visible or cache_key != _current_cache_key:
		return
	_preview.texture = null
	_status.text = NotLightL10n.text("formula.editor.error", {"message": message})
	_last_error_detail = detail
	_details.text = detail
	_details_button.visible = not detail.is_empty()
	_details.visible = false


func _on_backend_status_changed() -> void:
	_refresh_backend_status()
	if visible:
		_schedule_preview(true)


func _refresh_backend_status() -> void:
	if _status == null or _service == null:
		return
	if visible and not _service.backend_available():
		_status.text = _service.backend_status_text()


func _select_mode(mode: int) -> void:
	for index: int in range(_mode_option.item_count):
		if _mode_option.get_item_id(index) == mode:
			_mode_option.select(index)
			return


func _copy_latex() -> void:
	DisplayServer.clipboard_set(FormulaStore.normalize_source(_source_edit.text))
	NotLightL10n.bind_text(_status, "formula.editor.copied")


func _cancel() -> void:
	close_editor()
	canceled.emit()


func _apply() -> void:
	var record: Dictionary = current_record()
	if str(record.get("source_latex", "")).strip_edges().is_empty():
		NotLightL10n.bind_text(_status, "formula.error.empty")
		return
	apply_requested.emit(record)
