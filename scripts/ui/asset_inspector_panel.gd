# SPDX-License-Identifier: GPL-3.0-or-later
class_name AssetInspectorPanel
extends PanelContainer

signal close_requested
signal asset_updated(asset_id: String)

const DESCRIPTION_SAVE_DELAY: float = 1.10

var library: AssetLibraryService
var _pdf_media: PdfMediaService
var _pdf_optimizer: PdfOptimizationService
var _allow_destructive_pdf_variants: bool = true
var asset_id: String = ""
var _record: Dictionary = {}
var _name_label: Label
var _kind_label: Label
var _description_edit: TextEdit
var _tag_edit: LineEdit
var _tag_flow: HFlowContainer
var _usage_label: Label
var _technical_label: Label
var _pdf_section: VBoxContainer
var _pdf_status_label: Label
var _pdf_optimize_lossless_button: Button
var _pdf_optimize_balanced_button: Button
var _pdf_cancel_button: Button
var _pdf_use_original_button: Button
var _pdf_use_optimized_button: Button
var _pdf_delete_optimized_button: Button
var _save_label: Label
var _save_timer: Timer
var _suppress_edits: bool = false
var _dirty_description: bool = false
var _self_library_update_depth: int = 0


func _ready() -> void:
	theme_type_variation = "AssetInspectorPanel"
	clip_contents = true
	custom_minimum_size = Vector2(300.0, 0.0)
	_build_ui()
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = DESCRIPTION_SAVE_DELAY
	_save_timer.timeout.connect(_flush_description)
	add_child(_save_timer)
	NotLightL10n.connect_locale_changed(_on_locale_changed)


func configure(
	service: AssetLibraryService,
	pdf_service: PdfMediaService = null,
	pdf_optimization_service: PdfOptimizationService = null,
	allow_destructive_pdf_variants: bool = true
) -> void:
	library = service
	_pdf_media = pdf_service
	_pdf_optimizer = pdf_optimization_service
	_allow_destructive_pdf_variants = allow_destructive_pdf_variants
	if library != null and not library.library_changed.is_connected(_on_library_changed):
		library.library_changed.connect(_on_library_changed)
	if library != null and not library.asset_metadata_changed.is_connected(_on_asset_metadata_changed):
		library.asset_metadata_changed.connect(_on_asset_metadata_changed)
	if _pdf_media != null and not _pdf_media.variant_state_changed.is_connected(_on_pdf_variant_state_changed):
		_pdf_media.variant_state_changed.connect(_on_pdf_variant_state_changed)
	if _pdf_optimizer != null:
		if not _pdf_optimizer.optimization_progress.is_connected(_on_pdf_optimization_progress):
			_pdf_optimizer.optimization_progress.connect(_on_pdf_optimization_progress)
		if not _pdf_optimizer.optimization_failed.is_connected(_on_pdf_optimization_failed):
			_pdf_optimizer.optimization_failed.connect(_on_pdf_optimization_failed)
		if not _pdf_optimizer.optimization_completed.is_connected(_on_pdf_optimization_completed):
			_pdf_optimizer.optimization_completed.connect(_on_pdf_optimization_completed)
	_refresh_pdf_controls()


func show_asset(next_asset_id: String) -> void:
	flush_pending()
	asset_id = next_asset_id.strip_edges()
	visible = not asset_id.is_empty()
	_refresh_record()


func clear_asset() -> void:
	flush_pending()
	asset_id = ""
	_record.clear()
	visible = false


func flush_pending() -> void:
	if _save_timer != null:
		_save_timer.stop()
	if _dirty_description:
		_flush_description()


func _exit_tree() -> void:
	flush_pending()


func _build_ui() -> void:
	var outer_margin: MarginContainer = MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 16)
	outer_margin.add_theme_constant_override("margin_top", 16)
	outer_margin.add_theme_constant_override("margin_right", 12)
	outer_margin.add_theme_constant_override("margin_bottom", 16)
	add_child(outer_margin)

	var shell: VBoxContainer = VBoxContainer.new()
	shell.add_theme_constant_override("separation", 10)
	outer_margin.add_child(shell)

	# Keep the title/close action fixed while long descriptions, tags and
	# technical metadata scroll below it. This prevents the inspector itself
	# from becoming taller than the Hub or compact board drawer.
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	shell.add_child(header)
	var heading: Label = Label.new()
	NotLightL10n.bind_text(heading, "library.inspector.title")
	heading.theme_type_variation = "SectionLabel"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var close_button: Button = Button.new()
	close_button.text = "×"
	NotLightL10n.bind_tooltip(close_button, "library.inspector.close")
	close_button.theme_type_variation = "IconButton"
	close_button.custom_minimum_size = Vector2(34.0, 34.0)
	close_button.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(close_button)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	scroll.follow_focus = true
	shell.add_child(scroll)

	var body_margin: MarginContainer = MarginContainer.new()
	body_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_margin.add_theme_constant_override("margin_right", 4)
	body_margin.add_theme_constant_override("margin_bottom", 4)
	scroll.add_child(body_margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	body_margin.add_child(root)

	_name_label = Label.new()
	_name_label.theme_type_variation = "TitleLabel"
	_name_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	root.add_child(_name_label)
	_kind_label = Label.new()
	_kind_label.theme_type_variation = "CaptionLabel"
	root.add_child(_kind_label)

	_add_section_label(root, "library.inspector.description")
	_description_edit = TextEdit.new()
	_description_edit.theme_type_variation = "InspectorTextEdit"
	_description_edit.custom_minimum_size = Vector2(0.0, 124.0)
	_description_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	NotLightL10n.bind_placeholder_text(_description_edit, "library.inspector.description_placeholder")
	_description_edit.text_changed.connect(_on_description_changed)
	_description_edit.focus_exited.connect(_flush_description)
	root.add_child(_description_edit)

	var save_row: HBoxContainer = HBoxContainer.new()
	root.add_child(save_row)
	var save_spacer: Control = Control.new()
	save_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(save_spacer)
	_save_label = Label.new()
	_save_label.theme_type_variation = "CaptionLabel"
	save_row.add_child(_save_label)

	_add_section_label(root, "library.inspector.tags")
	# A flow row keeps the editor usable when the inspector is squeezed by a
	# narrow Hub viewport. Unlike HBoxContainer it can move the action to the
	# next line instead of increasing the inspector's minimum width and getting
	# clipped by its host.
	var tag_row: HFlowContainer = HFlowContainer.new()
	tag_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag_row.add_theme_constant_override("h_separation", 8)
	tag_row.add_theme_constant_override("v_separation", 6)
	root.add_child(tag_row)
	_tag_edit = LineEdit.new()
	NotLightL10n.bind_placeholder_text(_tag_edit, "library.inspector.tag_placeholder")
	_tag_edit.custom_minimum_size = Vector2(168.0, 0.0)
	_tag_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tag_edit.text_submitted.connect(func(_value: String) -> void: _add_tag_from_edit())
	tag_row.add_child(_tag_edit)
	var add_tag: Button = Button.new()
	NotLightL10n.bind_text(add_tag, "library.inspector.add_tag")
	add_tag.theme_type_variation = "GhostButton"
	add_tag.pressed.connect(_add_tag_from_edit)
	tag_row.add_child(add_tag)
	_tag_flow = HFlowContainer.new()
	_tag_flow.add_theme_constant_override("h_separation", 6)
	_tag_flow.add_theme_constant_override("v_separation", 6)
	root.add_child(_tag_flow)

	var separator_a: HSeparator = HSeparator.new()
	root.add_child(separator_a)
	_add_section_label(root, "library.inspector.usage")
	_usage_label = Label.new()
	_usage_label.theme_type_variation = "BodyMutedLabel"
	_usage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_usage_label)

	var separator_b: HSeparator = HSeparator.new()
	root.add_child(separator_b)
	_add_section_label(root, "library.inspector.technical")
	_technical_label = Label.new()
	_technical_label.theme_type_variation = "CaptionLabel"
	_technical_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	root.add_child(_technical_label)

	_pdf_section = VBoxContainer.new()
	_pdf_section.visible = false
	_pdf_section.add_theme_constant_override("separation", 8)
	root.add_child(_pdf_section)
	var pdf_separator: HSeparator = HSeparator.new()
	_pdf_section.add_child(pdf_separator)
	_add_section_label(_pdf_section, "library.inspector.pdf_optimization")
	_pdf_status_label = Label.new()
	_pdf_status_label.theme_type_variation = "BodyMutedLabel"
	_pdf_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pdf_section.add_child(_pdf_status_label)

	# PDF actions are intentionally flow layouts: localized button labels must
	# wrap as whole controls instead of forcing the inspector beyond its host.
	var pdf_optimize_row: HFlowContainer = HFlowContainer.new()
	pdf_optimize_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pdf_optimize_row.add_theme_constant_override("h_separation", 6)
	pdf_optimize_row.add_theme_constant_override("v_separation", 6)
	_pdf_section.add_child(pdf_optimize_row)
	_pdf_optimize_lossless_button = Button.new()
	NotLightL10n.bind_text(_pdf_optimize_lossless_button, "pdf.inspector.optimize_lossless")
	_pdf_optimize_lossless_button.theme_type_variation = "GhostButton"
	_pdf_optimize_lossless_button.pressed.connect(_on_pdf_optimize_lossless)
	pdf_optimize_row.add_child(_pdf_optimize_lossless_button)
	_pdf_optimize_balanced_button = Button.new()
	NotLightL10n.bind_text(_pdf_optimize_balanced_button, "pdf.inspector.optimize_balanced")
	NotLightL10n.bind_tooltip(_pdf_optimize_balanced_button, "pdf.inspector.optimize_balanced_help")
	_pdf_optimize_balanced_button.theme_type_variation = "GhostButton"
	_pdf_optimize_balanced_button.pressed.connect(_on_pdf_optimize_balanced)
	pdf_optimize_row.add_child(_pdf_optimize_balanced_button)
	_pdf_cancel_button = Button.new()
	NotLightL10n.bind_text(_pdf_cancel_button, "common.cancel")
	_pdf_cancel_button.theme_type_variation = "GhostButton"
	_pdf_cancel_button.visible = false
	_pdf_cancel_button.pressed.connect(_on_pdf_cancel_optimization)
	pdf_optimize_row.add_child(_pdf_cancel_button)

	var pdf_variant_row: HFlowContainer = HFlowContainer.new()
	pdf_variant_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pdf_variant_row.add_theme_constant_override("h_separation", 6)
	pdf_variant_row.add_theme_constant_override("v_separation", 6)
	_pdf_section.add_child(pdf_variant_row)
	_pdf_use_original_button = Button.new()
	NotLightL10n.bind_text(_pdf_use_original_button, "pdf.inspector.use_original")
	_pdf_use_original_button.theme_type_variation = "GhostButton"
	_pdf_use_original_button.pressed.connect(_on_pdf_use_original)
	pdf_variant_row.add_child(_pdf_use_original_button)
	_pdf_use_optimized_button = Button.new()
	NotLightL10n.bind_text(_pdf_use_optimized_button, "pdf.inspector.use_optimized")
	_pdf_use_optimized_button.theme_type_variation = "GhostButton"
	_pdf_use_optimized_button.pressed.connect(_on_pdf_use_optimized)
	pdf_variant_row.add_child(_pdf_use_optimized_button)
	_pdf_delete_optimized_button = Button.new()
	NotLightL10n.bind_text(_pdf_delete_optimized_button, "pdf.inspector.delete_optimized")
	_pdf_delete_optimized_button.theme_type_variation = "GhostButton"
	_pdf_delete_optimized_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pdf_delete_optimized_button.clip_text = true
	_pdf_delete_optimized_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pdf_delete_optimized_button.tooltip_text = _pdf_delete_optimized_button.text
	_pdf_delete_optimized_button.visible = _allow_destructive_pdf_variants
	_pdf_delete_optimized_button.pressed.connect(_on_pdf_delete_optimized)
	_pdf_section.add_child(_pdf_delete_optimized_button)


func _add_section_label(parent: VBoxContainer, key: String) -> void:
	var label: Label = Label.new()
	label.text = NotLightL10n.text(key)
	label.theme_type_variation = "CaptionStrongLabel"
	parent.add_child(label)


func _refresh_record(preserve_description_state: bool = false) -> void:
	if library == null or asset_id.is_empty():
		return
	var record: Dictionary = library.get_asset(asset_id)
	if record.is_empty():
		clear_asset()
		return
	var caret_line: int = 0
	var caret_column: int = 0
	var scroll_vertical: float = 0.0
	var scroll_horizontal: int = 0
	if preserve_description_state and _description_edit != null:
		caret_line = _description_edit.get_caret_line()
		caret_column = _description_edit.get_caret_column()
		scroll_vertical = _description_edit.scroll_vertical
		scroll_horizontal = _description_edit.scroll_horizontal
	_record = record
	_suppress_edits = true
	_name_label.text = str(record.get("display_name", NotLightL10n.text("library.resource")))
	_kind_label.text = NotLightL10n.text("ui.format.two_parts") % [AssetKinds.label(int(record.get("kind", AssetKinds.OTHER))), str(record.get("extension", "")).to_upper()]
	var next_description: String = str(record.get("description", ""))
	if _description_edit.text != next_description:
		_description_edit.text = next_description
		if preserve_description_state:
			var safe_line: int = clampi(caret_line, 0, maxi(0, _description_edit.get_line_count() - 1))
			var safe_column: int = clampi(caret_column, 0, _description_edit.get_line(safe_line).length())
			_description_edit.set_caret_line(safe_line, false)
			_description_edit.set_caret_column(safe_column, false)
			_description_edit.scroll_vertical = scroll_vertical
			_description_edit.scroll_horizontal = scroll_horizontal
	_suppress_edits = false
	_dirty_description = false
	_save_label.text = ""
	_refresh_tags()
	_refresh_usage()
	_refresh_technical()
	_refresh_pdf_controls()


func _refresh_tags() -> void:
	for child: Node in _tag_flow.get_children():
		child.queue_free()
	for tag: String in _tags_from_record():
		var button: Button = Button.new()
		button.text = NotLightL10n.text("ui.format.hash_tag_remove") % tag
		NotLightL10n.bind_tooltip(button, "common.remove")
		button.theme_type_variation = "TagButton"
		button.pressed.connect(_remove_tag.bind(tag))
		_tag_flow.add_child(button)


func _refresh_usage() -> void:
	var board_entries: Array[Dictionary] = _usage_entries(_record.get("used_on_board_entries", []))
	var note_entries: Array[Dictionary] = _usage_entries(_record.get("embedded_in_note_entries", []))
	var feature_labels: PackedStringArray = _clean_name_list(_record.get("used_by_features", []))
	var board_count: int = int(_record.get("board_usage_count", board_entries.size()))
	var note_count: int = int(_record.get("note_embed_usage_count", note_entries.size()))
	var feature_count: int = int(_record.get("feature_usage_count", feature_labels.size()))
	var lines: PackedStringArray = PackedStringArray()
	if board_count > 0:
		lines.append(NotLightL10n.text("library.inspector.usage_boards", {"count": board_count}))
		for label: String in _usage_entry_labels(board_entries, _record.get("used_on_boards", []), false):
			lines.append(NotLightL10n.text("ui.format.bullet") % label)
	if note_count > 0:
		if not lines.is_empty():
			lines.append("")
		lines.append(NotLightL10n.text("library.inspector.usage_notes", {"count": note_count}))
		for label: String in _usage_entry_labels(note_entries, _record.get("embedded_in_notes", []), true):
			lines.append(NotLightL10n.text("ui.format.bullet") % label)
	if feature_count > 0:
		if not lines.is_empty():
			lines.append("")
		lines.append(NotLightL10n.text("library.inspector.usage_features", {"count": feature_count}))
		for label: String in feature_labels:
			lines.append(NotLightL10n.text("ui.format.bullet") % label)
	if lines.is_empty():
		NotLightL10n.bind_text(_usage_label, "library.inspector.used_nowhere")
	else:
		_usage_label.text = "\n".join(lines)


func _usage_entries(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is not Array:
		return result
	for raw_entry: Variant in value as Array:
		if raw_entry is Dictionary:
			result.append((raw_entry as Dictionary).duplicate(true))
	return result


func _usage_entry_labels(entries: Array[Dictionary], fallback_names: Variant, include_folder: bool) -> PackedStringArray:
	if entries.is_empty():
		return _clean_name_list(fallback_names)
	var counts_by_name: Dictionary = {}
	for entry: Dictionary in entries:
		var clean_name: String = str(entry.get("name", entry.get("id", ""))).strip_edges()
		counts_by_name[clean_name] = int(counts_by_name.get(clean_name, 0)) + 1
	var labels: PackedStringArray = PackedStringArray()
	for entry: Dictionary in entries:
		var entry_id: String = str(entry.get("id", "")).strip_edges()
		var name: String = str(entry.get("name", entry_id)).strip_edges()
		if name.is_empty():
			name = entry_id
		var folder_path: String = str(entry.get("folder_path", "")).strip_edges() if include_folder else ""
		if not folder_path.is_empty():
			name = NotLightL10n.text("ui.format.name_folder") % [name, folder_path]
		elif int(counts_by_name.get(name, 0)) > 1 and not entry_id.is_empty():
			name = NotLightL10n.text("ui.format.name_id_tail") % [name, entry_id.right(8)]
		labels.append(name)
	return labels


func _clean_name_list(value: Variant) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if value is not Array and value is not PackedStringArray:
		return result
	for raw_name: Variant in value:
		var clean: String = str(raw_name).strip_edges()
		if not clean.is_empty() and not result.has(clean):
			result.append(clean)
	return result


func _refresh_technical() -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(NotLightL10n.text("ui.format.label_value") % [NotLightL10n.text("library.inspector.original_name"), str(_record.get("original_filename", ""))])
	lines.append(NotLightL10n.text("ui.format.label_value") % [NotLightL10n.text("library.inspector.type"), AssetKinds.label(int(_record.get("kind", AssetKinds.OTHER)))])
	lines.append(NotLightL10n.text("ui.format.label_value") % [NotLightL10n.text("library.inspector.size"), _format_bytes(int(_record.get("byte_size", 0)))])
	lines.append(NotLightL10n.text("library.inspector.id") % asset_id)
	var metadata_value: Variant = _record.get("metadata", {})
	if metadata_value is Dictionary:
		var metadata: Dictionary = metadata_value as Dictionary
		var width: int = int(metadata.get("width", 0))
		var height: int = int(metadata.get("height", 0))
		if width > 0 and height > 0:
			lines.append(NotLightL10n.text("ui.format.dimensions_px") % [width, height])
		var pdf_value: Variant = metadata.get("pdf", {})
		if pdf_value is Dictionary:
			var pdf: Dictionary = pdf_value as Dictionary
			var page_count: int = maxi(0, int(pdf.get("page_count", 0)))
			if page_count > 0:
				lines.append(NotLightL10n.text("ui.format.label_integer") % [NotLightL10n.text("library.inspector.pdf_pages"), page_count])
			var page_width: float = float(pdf.get("page_width_points", 0.0))
			var page_height: float = float(pdf.get("page_height_points", 0.0))
			if page_width > 0.0 and page_height > 0.0:
				lines.append(NotLightL10n.text("ui.format.pdf_page_size_points") % [NotLightL10n.text("library.inspector.pdf_page_size"), page_width, page_height])
			if bool(pdf.get("encrypted", false)):
				lines.append(NotLightL10n.text("ui.format.label_value") % [NotLightL10n.text("library.inspector.pdf_encrypted"), NotLightL10n.text("common.yes")])
			var renderer_version: String = str(pdf.get("poppler_version", "")).strip_edges()
			if not renderer_version.is_empty():
				lines.append(NotLightL10n.text("ui.format.label_value") % [NotLightL10n.text("library.inspector.pdf_renderer"), renderer_version])
	_technical_label.text = "\n".join(lines)


func _refresh_pdf_controls(status_override: String = "") -> void:
	if _pdf_section == null:
		return
	var is_pdf: bool = not asset_id.is_empty() and int(_record.get("kind", AssetKinds.OTHER)) == AssetKinds.PDF
	_pdf_section.visible = is_pdf
	if not is_pdf:
		return
	var state: Dictionary = _pdf_media.get_variant_state(asset_id) if _pdf_media != null else {}
	var variants: Dictionary = state.get("variants", {}) as Dictionary
	var original: Dictionary = variants.get(PdfMediaService.VARIANT_ORIGINAL, {}) as Dictionary
	var optimized: Dictionary = variants.get(PdfMediaService.VARIANT_OPTIMIZED, {}) as Dictionary
	var has_original: bool = _pdf_media != null and _pdf_media.has_variant(asset_id, PdfMediaService.VARIANT_ORIGINAL)
	var has_optimized: bool = _pdf_media != null and _pdf_media.has_variant(asset_id, PdfMediaService.VARIANT_OPTIMIZED)
	var preferred: String = _pdf_media.preferred_variant(asset_id) if _pdf_media != null else PdfMediaService.VARIANT_ORIGINAL
	var optimizing: bool = _pdf_optimizer != null and _pdf_optimizer.is_optimizing(asset_id)
	var parts: PackedStringArray = PackedStringArray()
	if has_original:
		parts.append(NotLightL10n.text("pdf.variant.original_size", {"size": _format_bytes(int(original.get("byte_size", 0))) }))
	if has_optimized:
		parts.append(NotLightL10n.text("pdf.variant.optimized_size", {"size": _format_bytes(int(optimized.get("byte_size", 0))) }))
		var active_label: String = NotLightL10n.text("pdf.variant.optimized" if preferred == PdfMediaService.VARIANT_OPTIMIZED else "pdf.variant.original")
		parts.append(NotLightL10n.text("pdf.variant.active", {"variant": active_label}))
	if not status_override.is_empty():
		parts.append(status_override)
	elif _pdf_optimizer != null and not optimizing:
		parts.append(_pdf_optimizer.status_text())
	elif optimizing:
		parts.append(NotLightL10n.text("pdf.inspector.optimizing"))
	_pdf_status_label.text = "\n".join(parts)
	# Idle state shows only optimization choices; an active job replaces them
	# with a single Cancel action. This avoids a permanently disabled third
	# button consuming scarce horizontal space and makes the current action clear.
	_pdf_optimize_lossless_button.visible = not optimizing
	_pdf_optimize_balanced_button.visible = not optimizing
	_pdf_cancel_button.visible = optimizing
	_pdf_optimize_lossless_button.disabled = _pdf_optimizer == null or optimizing or not has_original
	_pdf_optimize_balanced_button.disabled = _pdf_optimizer == null or optimizing or not has_original
	_pdf_cancel_button.disabled = _pdf_optimizer == null or not optimizing
	_pdf_use_original_button.disabled = optimizing or not has_original or preferred == PdfMediaService.VARIANT_ORIGINAL
	_pdf_use_optimized_button.disabled = optimizing or not has_optimized or preferred == PdfMediaService.VARIANT_OPTIMIZED
	_pdf_delete_optimized_button.visible = _allow_destructive_pdf_variants
	_pdf_delete_optimized_button.disabled = optimizing or not has_optimized or not _allow_destructive_pdf_variants


func _on_pdf_optimize_lossless() -> void:
	if _pdf_optimizer == null or not _pdf_optimizer.enqueue_optimization(asset_id, PdfOptimizationService.PRESET_LOSSLESS):
		_refresh_pdf_controls(_pdf_optimizer.status_text() if _pdf_optimizer != null else NotLightL10n.text("pdf.optimize.enqueue_failed"))


func _on_pdf_optimize_balanced() -> void:
	if _pdf_optimizer == null or not _pdf_optimizer.enqueue_optimization(asset_id, PdfOptimizationService.PRESET_BALANCED):
		_refresh_pdf_controls(_pdf_optimizer.status_text() if _pdf_optimizer != null else NotLightL10n.text("pdf.optimize.enqueue_failed"))


func _on_pdf_cancel_optimization() -> void:
	if _pdf_optimizer != null:
		_pdf_optimizer.cancel_optimization(asset_id)


func _on_pdf_use_original() -> void:
	if _pdf_media == null or not _pdf_media.set_preferred_variant(asset_id, PdfMediaService.VARIANT_ORIGINAL):
		_refresh_pdf_controls(NotLightL10n.text("pdf.variant.original_unavailable"))


func _on_pdf_use_optimized() -> void:
	if _pdf_media == null or not _pdf_media.set_preferred_variant(asset_id, PdfMediaService.VARIANT_OPTIMIZED):
		_refresh_pdf_controls(NotLightL10n.text("pdf.variant.optimized_unavailable"))


func _on_pdf_delete_optimized() -> void:
	if _pdf_media == null or not _pdf_media.delete_optimized_variant(asset_id):
		_refresh_pdf_controls(NotLightL10n.text("pdf.variant.delete_optimized_failed"))


func _on_pdf_variant_state_changed(changed_asset_id: String, _state: Dictionary) -> void:
	if changed_asset_id == asset_id:
		_record = library.get_asset(asset_id) if library != null else _record
		_refresh_technical()
		_refresh_pdf_controls()


func _on_pdf_optimization_progress(changed_asset_id: String, _progress: float, message: String) -> void:
	if changed_asset_id == asset_id:
		_refresh_pdf_controls(message)


func _on_pdf_optimization_failed(changed_asset_id: String, message: String) -> void:
	if changed_asset_id == asset_id:
		_record = library.get_asset(asset_id) if library != null else _record
		_refresh_pdf_controls(message)


func _on_pdf_optimization_completed(changed_asset_id: String, _optimized_path: String, _saved_bytes: int) -> void:
	if changed_asset_id == asset_id:
		_record = library.get_asset(asset_id) if library != null else _record
		_refresh_technical()
		_refresh_pdf_controls(NotLightL10n.text("pdf.optimize.completed"))


func _on_description_changed() -> void:
	if _suppress_edits or asset_id.is_empty():
		return
	_dirty_description = true
	NotLightL10n.bind_text(_save_label, "library.inspector.save_pending")
	_save_timer.start()


func _flush_description() -> void:
	if not _dirty_description or library == null or asset_id.is_empty():
		return
	_save_timer.stop()
	var description: String = _description_edit.text
	var tags: PackedStringArray = _tags_from_record()
	if _update_asset_details_without_self_refresh(description, tags):
		_dirty_description = false
		_record = library.get_asset(asset_id)
		NotLightL10n.bind_text(_save_label, "library.inspector.saved")
		asset_updated.emit(asset_id)
	else:
		# Keep the authored text dirty. A transient storage failure must never turn
		# the visible editor state into a false "saved" state or discard it on the
		# next unrelated Library refresh.
		_dirty_description = true
		NotLightL10n.bind_text(_save_label, "library.inspector.save_error")


func _add_tag_from_edit() -> void:
	if library == null or asset_id.is_empty():
		return
	var tag: String = _tag_edit.text.strip_edges()
	while tag.begins_with("#"):
		tag = tag.trim_prefix("#").strip_edges()
	if tag.is_empty():
		return
	var tags: PackedStringArray = _tags_from_record()
	for current: String in tags:
		if current.to_lower() == tag.to_lower():
			_tag_edit.clear()
			return
	tags.append(tag.left(48))
	_tag_edit.clear()
	_save_tags(tags)


func _remove_tag(tag: String) -> void:
	var next: PackedStringArray = PackedStringArray()
	for current: String in _tags_from_record():
		if current.to_lower() != tag.to_lower():
			next.append(current)
	_save_tags(next)


func _save_tags(tags: PackedStringArray) -> void:
	if library == null or asset_id.is_empty():
		return
	_save_timer.stop()
	var description: String = _description_edit.text
	var description_was_dirty: bool = _dirty_description
	if _update_asset_details_without_self_refresh(description, tags):
		_record = library.get_asset(asset_id)
		_dirty_description = false
		NotLightL10n.bind_text(_save_label, "library.inspector.saved")
		_refresh_tags()
		asset_updated.emit(asset_id)
	else:
		_dirty_description = description_was_dirty
		NotLightL10n.bind_text(_save_label, "library.inspector.save_error")


func _update_asset_details_without_self_refresh(description: String, tags: PackedStringArray) -> bool:
	if library == null or asset_id.is_empty():
		return false
	_self_library_update_depth += 1
	var updated: bool = library.update_asset_details(asset_id, description, tags)
	_self_library_update_depth = maxi(0, _self_library_update_depth - 1)
	return updated


func _tags_from_record() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var raw_tags: Variant = _record.get("tags", [])
	if raw_tags is Array or raw_tags is PackedStringArray:
		for raw_tag: Variant in raw_tags:
			var tag: String = str(raw_tag).strip_edges()
			if not tag.is_empty():
				result.append(tag)
	return result


func _on_library_changed() -> void:
	if asset_id.is_empty() or _dirty_description or _self_library_update_depth > 0:
		return
	# Library changes can be unrelated to this asset (preview cache, PDF variant,
	# another card, etc.). Preserve caret/scroll even when the current record did
	# change so background activity never steals the writer's insertion point.
	_refresh_record(true)


func _on_asset_metadata_changed(changed_asset_id: String) -> void:
	if changed_asset_id != asset_id or asset_id.is_empty():
		return
	if _dirty_description or _self_library_update_depth > 0:
		return
	_refresh_record(true)


func _on_locale_changed(_locale: String) -> void:
	# The inspector is cheap to rebuild and this keeps every visible string
	# sourced from the centralized JSON bundle.
	if not is_inside_tree():
		return
	var current_id: String = asset_id
	flush_pending()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_save_timer = null
	_name_label = null
	_kind_label = null
	_description_edit = null
	_tag_edit = null
	_tag_flow = null
	_usage_label = null
	_technical_label = null
	_pdf_section = null
	_pdf_status_label = null
	_pdf_optimize_lossless_button = null
	_pdf_optimize_balanced_button = null
	_pdf_cancel_button = null
	_pdf_use_original_button = null
	_pdf_use_optimized_button = null
	_pdf_delete_optimized_button = null
	_save_label = null
	_build_ui()
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = DESCRIPTION_SAVE_DELAY
	_save_timer.timeout.connect(_flush_description)
	add_child(_save_timer)
	asset_id = current_id
	if not asset_id.is_empty():
		_refresh_record()


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
