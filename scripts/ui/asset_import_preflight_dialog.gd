# SPDX-License-Identifier: GPL-3.0-or-later
class_name AssetImportPreflightDialog
extends Window

signal import_requested(results: Array)
signal cancel_requested

const DEFAULT_SIZE: Vector2i = Vector2i(900, 650)
const MIN_DIALOG_SIZE: Vector2i = Vector2i(660, 470)
const PARENT_SIZE_RATIO: float = 0.94

var _heading: Label
var _helper: Label
var _folder_label: Label
var _summary_label: Label
var _progress_label: Label
var _progress_bar: ProgressBar
var _rows: VBoxContainer
var _import_button: Button
var _results: Array[ImportCandidateResult] = []
var _checks: Array[CheckBox] = []
var _loading: bool = false
var _total_count: int = 0
var _folder_name: String = ""


func _init() -> void:
	visible = false


func _ready() -> void:
	size = DEFAULT_SIZE
	min_size = MIN_DIALOG_SIZE
	max_size = Vector2i.ZERO
	borderless = true
	transient = true
	exclusive = true
	unresizable = false
	close_requested.connect(_request_close)
	_build_ui()
	NotLightL10n.connect_locale_changed(_on_locale_changed)


func open_loading(folder_name: String, total_count: int) -> void:
	_folder_name = folder_name
	_total_count = maxi(0, total_count)
	_loading = true
	_results.clear()
	_checks.clear()
	_clear_rows()
	_refresh_static_text()
	NotLightL10n.bind_text(_helper, "library.preflight.checking_help")
	_progress_label.text = NotLightL10n.text("library.preflight.checking", {"done": 0, "total": _total_count})
	_progress_bar.value = 0.0
	_progress_bar.visible = true
	_summary_label.text = ""
	_import_button.disabled = true
	popup_centered_clamped(DEFAULT_SIZE, PARENT_SIZE_RATIO)


func set_validation_progress(completed_count: int, total_count: int, source_path: String) -> void:
	if not _loading:
		return
	var total: int = maxi(1, total_count)
	var completed: int = clampi(completed_count, 0, total)
	_progress_label.text = NotLightL10n.text("library.preflight.checking_file", {
		"done": completed,
		"total": total,
		"name": source_path.get_file(),
	})
	_progress_bar.value = float(completed) * 100.0 / float(total)


func show_results(results: Array, folder_name: String) -> void:
	_loading = false
	_folder_name = folder_name
	_results.clear()
	for value: Variant in results:
		if value is ImportCandidateResult:
			_results.append(value as ImportCandidateResult)
	_total_count = _results.size()
	_progress_bar.visible = false
	_progress_label.text = ""
	NotLightL10n.bind_text(_helper, "library.preflight.ready_help")
	_rebuild_rows()
	_refresh_static_text()
	_refresh_summary()


func show_failure(message: String) -> void:
	_loading = false
	_results.clear()
	_checks.clear()
	_clear_rows()
	_progress_bar.visible = false
	_progress_label.text = ""
	_helper.text = message
	_import_button.disabled = true
	NotLightL10n.bind_text(_summary_label, "library.preflight.failed")


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_ESCAPE:
		_request_close()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.theme = NotLightTheme.create_theme()
	panel.theme_type_variation = "SettingsModalPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	content.add_child(header)
	_heading = Label.new()
	_heading.theme_type_variation = "TitleLabel"
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_heading)
	var close_button: Button = Button.new()
	close_button.text = "×"
	close_button.theme_type_variation = "IconButton"
	close_button.custom_minimum_size = Vector2(40.0, 40.0)
	close_button.pressed.connect(_request_close)
	header.add_child(close_button)

	_helper = Label.new()
	_helper.theme_type_variation = "BodyMutedLabel"
	_helper.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_helper)

	var context_row: HBoxContainer = HBoxContainer.new()
	context_row.add_theme_constant_override("separation", 8)
	content.add_child(context_row)
	var folder_caption: Label = Label.new()
	NotLightL10n.bind_text(folder_caption, "library.preflight.destination")
	folder_caption.theme_type_variation = "CaptionStrongLabel"
	context_row.add_child(folder_caption)
	_folder_label = Label.new()
	_folder_label.theme_type_variation = "CaptionLabel"
	_folder_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_folder_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	context_row.add_child(_folder_label)

	var progress_box: VBoxContainer = VBoxContainer.new()
	progress_box.add_theme_constant_override("separation", 5)
	content.add_child(progress_box)
	_progress_label = Label.new()
	_progress_label.theme_type_variation = "CaptionLabel"
	_progress_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	progress_box.add_child(_progress_label)
	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size = Vector2(0.0, 8.0)
	progress_box.add_child(_progress_bar)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	scroll.follow_focus = true
	content.add_child(scroll)
	var rows_margin: MarginContainer = MarginContainer.new()
	rows_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_margin.add_theme_constant_override("margin_right", 8)
	scroll.add_child(rows_margin)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 7)
	rows_margin.add_child(_rows)

	_summary_label = Label.new()
	_summary_label.theme_type_variation = "CaptionStrongLabel"
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_summary_label)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 9)
	content.add_child(actions)
	var cancel_button: Button = Button.new()
	cancel_button.theme_type_variation = "GhostButton"
	cancel_button.custom_minimum_size = Vector2(112.0, 42.0)
	NotLightL10n.bind_text(cancel_button, "common.cancel")
	cancel_button.pressed.connect(_request_close)
	actions.add_child(cancel_button)
	_import_button = Button.new()
	_import_button.theme_type_variation = "PrimaryButton"
	_import_button.custom_minimum_size = Vector2(190.0, 42.0)
	_import_button.pressed.connect(_submit)
	actions.add_child(_import_button)
	_refresh_static_text()


func _rebuild_rows() -> void:
	_clear_rows()
	_checks.clear()
	for index: int in range(_results.size()):
		var candidate: ImportCandidateResult = _results[index]
		var row_panel: PanelContainer = PanelContainer.new()
		row_panel.theme_type_variation = "AssetImportPanel"
		row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rows.add_child(row_panel)
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row_panel.add_child(row)

		var check: CheckBox = CheckBox.new()
		check.custom_minimum_size = Vector2(34.0, 42.0)
		check.button_pressed = candidate.is_importable()
		check.disabled = not candidate.is_importable()
		check.toggled.connect(_on_candidate_toggled.bind(index))
		row.add_child(check)
		_checks.append(check)

		var text_box: VBoxContainer = VBoxContainer.new()
		text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_box.add_theme_constant_override("separation", 2)
		row.add_child(text_box)
		var name_row: HBoxContainer = HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 8)
		text_box.add_child(name_row)
		var name_label: Label = Label.new()
		name_label.text = candidate.filename
		name_label.tooltip_text = candidate.source_path
		name_label.theme_type_variation = "CaptionStrongLabel"
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_row.add_child(name_label)
		var kind_label: Label = Label.new()
		kind_label.text = AssetKinds.short_label(candidate.expected_kind) if candidate.valid else NotLightL10n.text("performance.unavailable")
		kind_label.theme_type_variation = "CaptionLabel"
		kind_label.custom_minimum_size = Vector2(54.0, 0.0)
		kind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		name_row.add_child(kind_label)
		var size_label: Label = Label.new()
		size_label.text = _format_bytes(candidate.byte_size) if candidate.byte_size > 0 else NotLightL10n.text("performance.unavailable")
		size_label.theme_type_variation = "CaptionLabel"
		size_label.custom_minimum_size = Vector2(86.0, 0.0)
		size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		name_row.add_child(size_label)

		var status_label: Label = Label.new()
		status_label.theme_type_variation = "BodyMutedLabel"
		status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status_label.text = _candidate_description(candidate)
		status_label.tooltip_text = candidate.technical_detail
		text_box.add_child(status_label)


func _candidate_description(candidate: ImportCandidateResult) -> String:
	var parts: Array[String] = [candidate.status_message()]
	if candidate.valid:
		var metadata: Dictionary = candidate.metadata_preview
		if candidate.expected_kind == AssetKinds.PDF:
			var pages: int = int(metadata.get("page_count", 0))
			if pages > 0:
				parts.append(NotLightL10n.text("library.preflight.meta.pages", {"count": pages}))
			parts.append(NotLightL10n.text("library.preflight.meta.pdf_optimization"))
		elif candidate.expected_kind == AssetKinds.VIDEO:
			var width: int = int(metadata.get("width", 0))
			var height: int = int(metadata.get("height", 0))
			if width > 0 and height > 0:
				parts.append(NotLightL10n.text("ui.format.dimensions") % [width, height])
			var duration: float = float(metadata.get("duration", 0.0))
			if duration > 0.0:
				parts.append(_format_duration(duration))
		elif candidate.expected_kind == AssetKinds.AUDIO:
			var audio_duration: float = float(metadata.get("duration", 0.0))
			if audio_duration > 0.0:
				parts.append(_format_duration(audio_duration))
	return " · ".join(parts)


func _on_candidate_toggled(_pressed: bool, _index: int) -> void:
	_refresh_summary()


func _refresh_static_text() -> void:
	if _heading == null:
		return
	NotLightL10n.bind_text(_heading, "library.preflight.title")
	_folder_label.text = _folder_name if not _folder_name.strip_edges().is_empty() else NotLightL10n.text("library.folder.none")
	if _loading:
		_import_button.text = NotLightL10n.text("library.preflight.import", {"count": 0})
		_import_button.disabled = true


func _refresh_summary() -> void:
	var selected_count: int = 0
	var duplicate_count: int = 0
	var rejected_count: int = 0
	var repair_count: int = 0
	var selected_bytes: int = 0
	for index: int in range(_results.size()):
		var candidate: ImportCandidateResult = _results[index]
		if not candidate.valid:
			rejected_count += 1
		elif candidate.duplicate:
			duplicate_count += 1
		elif candidate.repair_existing:
			repair_count += 1
		if index < _checks.size() and _checks[index].button_pressed and candidate.is_importable():
			selected_count += 1
			selected_bytes += candidate.byte_size
	_summary_label.text = NotLightL10n.text("library.preflight.summary", {
		"selected": selected_count,
		"duplicates": duplicate_count,
		"rejected": rejected_count,
		"repair": repair_count,
		"size": _format_bytes(selected_bytes),
	})
	_import_button.text = NotLightL10n.text("library.preflight.import", {"count": selected_count})
	_import_button.disabled = selected_count <= 0


func _submit() -> void:
	if _loading:
		return
	var selected: Array[ImportCandidateResult] = []
	for index: int in range(_results.size()):
		if index >= _checks.size() or not _checks[index].button_pressed:
			continue
		var candidate: ImportCandidateResult = _results[index]
		if candidate.is_importable():
			selected.append(candidate)
	if selected.is_empty():
		return
	hide()
	import_requested.emit(selected)


func _request_close() -> void:
	if _loading:
		cancel_requested.emit()
	_loading = false
	hide()


func _clear_rows() -> void:
	if _rows == null:
		return
	for child: Node in _rows.get_children():
		child.queue_free()


func _format_bytes(byte_count: int) -> String:
	var value: float = float(maxi(0, byte_count))
	if value < 1024.0:
		return NotLightL10n.text("ui.format.bytes_b") % int(value)
	value /= 1024.0
	if value < 1024.0:
		return NotLightL10n.text("ui.format.bytes_kb") % value
	value /= 1024.0
	if value < 1024.0:
		return NotLightL10n.text("ui.format.bytes_mb") % value
	value /= 1024.0
	if value < 1024.0:
		return NotLightL10n.text("ui.format.bytes_gb") % value
	return NotLightL10n.text("ui.format.bytes_tib") % (value / 1024.0)


func _format_duration(seconds: float) -> String:
	var total: int = maxi(0, int(round(seconds)))
	var minutes: int = floori(float(total) / 60.0)
	var remaining: int = total % 60
	return NotLightL10n.text("ui.format.duration_minutes") % [minutes, remaining]


func _on_locale_changed(_locale: String) -> void:
	NotLightL10n.refresh_tree(self)
	_refresh_static_text()
	if not _loading and not _results.is_empty():
		_rebuild_rows()
		_refresh_summary()
